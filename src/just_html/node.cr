module JustHTML
  abstract class Node
    property parent : Node?
    getter children : Array(Node)
    abstract def name : String

    def initialize
      @parent = nil
      @children = [] of Node
    end

    def append_child(node : Node) : Node
      node.parent = self
      @children << node
      node
    end

    def remove_child(node : Node) : Node
      @children.delete(node)
      node.parent = nil
      node
    end

    def insert_before(node : Node, reference : Node?) : Node
      if reference.nil?
        return append_child(node)
      end
      index = @children.index(reference)
      raise ArgumentError.new("Reference node is not a child") unless index
      node.parent = self
      @children.insert(index, node)
      node
    end

    def replace_child(new_node : Node, old_node : Node) : Node
      index = @children.index(old_node)
      raise ArgumentError.new("Node to replace is not a child") unless index
      old_node.parent = nil
      new_node.parent = self
      @children[index] = new_node
      old_node
    end

    def has_child_nodes? : Bool
      !@children.empty?
    end

    def clone(deep : Bool = false) : Node
      raise NotImplementedError.new("Subclasses must implement clone")
    end
  end
end
