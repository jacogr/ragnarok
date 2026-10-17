## External callers cannot expose, retag or mutate state-layout result/metadata storage.
import ../../../src/codec/state_layout
discard StateNodeInfo(nodeKind: StateNodeKind.HashedLeaf)
