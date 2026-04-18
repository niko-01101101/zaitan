#pragma once
#include "Pane.hpp"
#include <memory>
#include <vector>

static constexpr int MAX_PANES = 10;

enum class SplitDirection { Horizontal, Vertical };

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

    bool assignWindow(uint32_t windowID);
    bool splitHorizontally(uint32_t windowID, uint32_t newWindowID = 0);
    bool splitVertically(uint32_t windowID, uint32_t newWindowID = 0);
    bool removeWindow(uint32_t windowID);

    std::vector<WindowPlacement> getLayout() const;
};
