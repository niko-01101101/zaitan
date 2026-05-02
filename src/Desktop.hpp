#pragma once
#include "Pane.hpp"
#include <memory>
#include <vector>

static constexpr int MAX_PANES = 10;

enum class SplitDirection { Horizontal, Vertical };
enum class HorizontalDirection { Left, Right };
enum class VerticalDirection { Up, Down };

struct WindowPlacement {
  uint32_t windowID;
  WMRect frame;
};

struct Node {
  WMRect frame;
  Node *parent = nullptr;
  SplitDirection split = SplitDirection::Horizontal;
  std::unique_ptr<Node> left, right;
  std::unique_ptr<Pane> pane; // non-null on leaf nodes

  bool isLeaf() const { return pane != nullptr; }
  bool isEmpty() const { return pane->windowID == 0; }
};

class Desktop {
private:
  std::unique_ptr<Node> root;
  int paneCount = 0;

  Node *findByWindowID(Node *node, uint32_t windowID);
  Node *findEmptyPane(Node *node);
  void reframe(Node *node, WMRect frame);
  bool splitNode(Node *node, SplitDirection dir, uint32_t newWindowID);
  void collectLayout(Node *node, std::vector<WindowPlacement> &out) const;

public:
  Desktop(WMRect screenFrame);

  bool containsWindow(uint32_t windowID);
  bool assignWindow(uint32_t windowID);
  bool splitHorizontally(uint32_t windowID, uint32_t newWindowID = 0);
  bool splitVertically(uint32_t windowID, uint32_t newWindowID = 0);
  bool removeWindow(uint32_t windowID);
  bool moveWindowHorizontally(uint32_t windowID, HorizontalDirection direction);
  bool moveWindowVertically(uint32_t windowID, VerticalDirection direction);
  uint32_t moveHorizontally(uint32_t selectedID, HorizontalDirection direction);
  uint32_t moveVertically(uint32_t selectedID, VerticalDirection direction);

  void flipSplits();

  std::vector<WindowPlacement> getLayout() const;
};
