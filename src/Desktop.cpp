#include "Desktop.hpp"

Node *Desktop::findByWindowID(Node *node, uint32_t windowID) {
  if (!node)
    return nullptr;
  if (node->isLeaf())
    return node->pane->windowID == windowID ? node : nullptr;
  Node *found = findByWindowID(node->left.get(), windowID);
  return found ? found : findByWindowID(node->right.get(), windowID);
}

Node *Desktop::findEmptyPane(Node *node) {
  if (!node)
    return nullptr;
  if (node->isLeaf())
    return node->pane->windowID == 0 ? node : nullptr;
  Node *found = findEmptyPane(node->left.get());
  return found ? found : findEmptyPane(node->right.get());
}

void Desktop::reframe(Node *node, WMRect frame) {
  node->frame = frame;
  if (node->isLeaf()) {
    node->pane->frame = frame;
    return;
  }
  WMRect l = frame, r = frame;
  if (node->split == SplitDirection::Horizontal) {
    l.width /= 2;
    r.x += l.width;
    r.width = frame.width - l.width;
  } else {
    l.height /= 2;
    r.y += l.height;
    r.height = frame.height - l.height;
  }
  reframe(node->left.get(), l);
  reframe(node->right.get(), r);
}

bool Desktop::splitNode(Node *node, SplitDirection dir, uint32_t newWindowID) {
  if (!node || !node->isLeaf() || paneCount >= MAX_PANES)
    return false;

  WMRect leftFrame = node->frame, rightFrame = node->frame;
  if (dir == SplitDirection::Horizontal) {
    leftFrame.width /= 2;
    rightFrame.x += leftFrame.width;
    rightFrame.width = node->frame.width - leftFrame.width;
  } else {
    leftFrame.height /= 2;
    rightFrame.y += leftFrame.height;
    rightFrame.height = node->frame.height - leftFrame.height;
  }

  node->pane->frame = leftFrame;
  node->left = std::make_unique<Node>();
  node->left->parent = node;
  node->left->frame = leftFrame;
  node->left->pane = std::move(node->pane);

  node->right = std::make_unique<Node>();
  node->right->parent = node;
  node->right->frame = rightFrame;
  node->right->pane = std::make_unique<Pane>(Pane{newWindowID, rightFrame});

  node->split = dir;
  paneCount++;
  return true;
}

void Desktop::collectLayout(Node *node,
                            std::vector<WindowPlacement> &out) const {
  if (!node)
    return;
  if (node->isLeaf()) {
    if (node->pane->windowID != 0)
      out.push_back({node->pane->windowID, node->pane->frame});
    return;
  }
  collectLayout(node->left.get(), out);
  collectLayout(node->right.get(), out);
}

Desktop::Desktop(WMRect screenFrame) {
  root = std::make_unique<Node>();
  root->frame = screenFrame;
  root->pane = std::make_unique<Pane>(Pane{0, screenFrame});
  paneCount = 1;
}

bool Desktop::assignWindow(uint32_t windowID) {
  if (findByWindowID(root.get(), windowID))
    return false;
  Node *node = findEmptyPane(root.get());
  if (!node)
    return false;
  node->pane->windowID = windowID;
  return true;
}

bool Desktop::splitHorizontally(uint32_t windowID, uint32_t newWindowID) {
  return splitNode(findByWindowID(root.get(), windowID),
                   SplitDirection::Horizontal, newWindowID);
}

bool Desktop::splitVertically(uint32_t windowID, uint32_t newWindowID) {
  return splitNode(findByWindowID(root.get(), windowID),
                   SplitDirection::Vertical, newWindowID);
}

bool Desktop::removeWindow(uint32_t windowID) {
  Node *node = findByWindowID(root.get(), windowID);
  if (!node)
    return false;

  if (paneCount == 1) {
    node->pane->windowID = 0;
    return true;
  }

  Node *parent = node->parent;
  bool nodeIsLeft = (parent->left.get() == node);
  std::unique_ptr<Node> sibling =
      std::move(nodeIsLeft ? parent->right : parent->left);

  reframe(sibling.get(), parent->frame);
  sibling->parent = parent->parent;

  if (parent->parent) {
    bool parentIsLeft = (parent->parent->left.get() == parent);
    (parentIsLeft ? parent->parent->left : parent->parent->right) =
        std::move(sibling);
  } else {
    root = std::move(sibling);
  }

  paneCount--;
  return true;
}

static void flipSplitDirs(Node *node) {
  if (!node || node->isLeaf())
    return;
  node->split = (node->split == SplitDirection::Horizontal)
                    ? SplitDirection::Vertical
                    : SplitDirection::Horizontal;
  flipSplitDirs(node->left.get());
  flipSplitDirs(node->right.get());
}

void Desktop::flipSplits() {
  flipSplitDirs(root.get());
  reframe(root.get(), root->frame);
}

std::vector<WindowPlacement> Desktop::getLayout() const {
  std::vector<WindowPlacement> layout;
  collectLayout(root.get(), layout);
  return layout;
}

static Node *leftmostLeaf(Node *node) {
  while (!node->isLeaf())
    node = node->left.get();
  return node;
}

static Node *rightmostLeaf(Node *node) {
  while (!node->isLeaf())
    node = node->right.get();
  return node;
}

bool Desktop::moveWindowHorizontally(uint32_t windowID,
                                     HorizontalDirection direction) {
  Node *node = findByWindowID(root.get(), windowID);
  if (!node)
    return false;

  Node *cur = node;
  Node *parent = cur->parent;
  while (parent) {
    if (parent->split == SplitDirection::Horizontal) {
      if (direction == HorizontalDirection::Left && parent->right.get() == cur) {
        Node *neighbor = rightmostLeaf(parent->left.get());
        std::swap(node->pane->windowID, neighbor->pane->windowID);
        return true;
      }
      if (direction == HorizontalDirection::Right && parent->left.get() == cur) {
        Node *neighbor = leftmostLeaf(parent->right.get());
        std::swap(node->pane->windowID, neighbor->pane->windowID);
        return true;
      }
    }
    cur = parent;
    parent = parent->parent;
  }
  return false;
}

bool Desktop::moveWindowVertically(uint32_t windowID,
                                   VerticalDirection direction) {
  Node *node = findByWindowID(root.get(), windowID);
  if (!node)
    return false;

  Node *cur = node;
  Node *parent = cur->parent;
  while (parent) {
    if (parent->split == SplitDirection::Vertical) {
      if (direction == VerticalDirection::Up && parent->right.get() == cur) {
        Node *neighbor = rightmostLeaf(parent->left.get());
        std::swap(node->pane->windowID, neighbor->pane->windowID);
        return true;
      }
      if (direction == VerticalDirection::Down && parent->left.get() == cur) {
        Node *neighbor = leftmostLeaf(parent->right.get());
        std::swap(node->pane->windowID, neighbor->pane->windowID);
        return true;
      }
    }
    cur = parent;
    parent = parent->parent;
  }
  return false;
}

uint32_t Desktop::moveHorizontally(uint32_t selectedID,
                                    HorizontalDirection direction) {
  Node *node = findByWindowID(root.get(), selectedID);
  if (!node)
    return 0;

  Node *cur = node;
  Node *parent = cur->parent;
  while (parent) {
    if (parent->split == SplitDirection::Horizontal) {
      if (direction == HorizontalDirection::Left && parent->right.get() == cur)
        return rightmostLeaf(parent->left.get())->pane->windowID;
      if (direction == HorizontalDirection::Right && parent->left.get() == cur)
        return leftmostLeaf(parent->right.get())->pane->windowID;
    }
    cur = parent;
    parent = parent->parent;
  }
  return 0;
}

uint32_t Desktop::moveVertically(uint32_t selectedID,
                                  VerticalDirection direction) {
  Node *node = findByWindowID(root.get(), selectedID);
  if (!node)
    return 0;

  Node *cur = node;
  Node *parent = cur->parent;
  while (parent) {
    if (parent->split == SplitDirection::Vertical) {
      if (direction == VerticalDirection::Up && parent->right.get() == cur)
        return rightmostLeaf(parent->left.get())->pane->windowID;
      if (direction == VerticalDirection::Down && parent->left.get() == cur)
        return leftmostLeaf(parent->right.get())->pane->windowID;
    }
    cur = parent;
    parent = parent->parent;
  }
  return 0;
}
