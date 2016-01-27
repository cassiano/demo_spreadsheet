# require 'pp'

require 'set'

class Object
  DEBUG = false

  def log(msg)
    puts "[#{Time.now}] #{msg}" if DEBUG
  end
end

class Spreadsheet
  attr_reader :cells

  def initialize
    @cells = {}
  end

  def cell_count
    cells.count
  end

  def get(addr)
    addr = addr.to_sym

    set addr
  end

  def set(addr, content = nil)
    addr = addr.to_sym

    if (cell = cells[addr])
      cell.tap { |c| c.content = content if content }
    else
      add_cell addr, content
    end
  end

  def consistent?
    true
  end

  private

  def add_cell(addr, content = nil)
    cell         = Cell.new(self, addr)
    cells[addr]  = cell
    cell.content = content if content

    cell
  end
end

class Cell
  DEFAULT_VALUE   = 0
  ADDR_PATTERN_RE = /[A-Z]+[1-9]\d*/i

  attr_reader :spreadsheet, :addr, :content, :references, :observers

  # List of possible exceptions.
  class CircularReferenceError < StandardError; end

  def initialize(spreadsheet, addr)
    @spreadsheet = spreadsheet
    @addr        = addr
    @references  = Set.new
    @observers   = Set.new
  end

  def content=(new_content)
    log "Changing #{addr} from `#{content}` to `#{new_content}`"

    return if new_content.to_s == content.to_s

    @content = new_content

    sync_references

    eval true
  end

  def eval(reevaluate = false)
    previous_evaluated_content = @evaluated_content

    @evaluated_content = nil if reevaluate

    @evaluated_content ||= begin
      log "Evaluating #{addr} (reevaluate: #{reevaluate})"

      if is_formula?
        evaluatable_content = formula.gsub(ADDR_PATTERN_RE) do |ref_addr|
          spreadsheet.get(ref_addr).eval
        end

        Kernel.eval evaluatable_content

        # values = formula.scan(ADDR_PATTERN_RE).inject({}) do |memo, ref_addr|
        #   memo[ref_addr.to_sym] = spreadsheet.set(ref_addr.to_sym).eval || DEFAULT_VALUE
        #   memo
        # end
        #
        # content_with_template_variables = formula.gsub(Regexp.new("(#{ADDR_PATTERN})", Regexp::IGNORECASE), '%{\1}')
        #
        # Kernel.eval content_with_template_variables % values
      else
        content
      end
    end

    notify_observers if previous_evaluated_content.to_s != @evaluated_content.to_s

    @evaluated_content || DEFAULT_VALUE
  end

  protected

  def is_formula?
    content.is_a?(String) && content.start_with?('=')
  end

  def formula
    content[1..-1] if is_formula?
  end

  def add_reference(reference)
    log "Adding reference #{reference.addr} to #{addr}"

    if reference.directly_or_indirectly_references?(self)
      raise CircularReferenceError, "Circular reference detected when adding #{reference.addr} to #{addr}"
    end

    references << reference

    reference.add_observer self
  end

  def remove_reference(reference)
    log "Removing reference #{reference.addr} from #{addr}"

    references.delete reference

    reference.remove_observer self
  end

  def add_observer(observer)
    log "Adding observer #{observer.addr} to #{addr}"

    observers << observer
  end

  def remove_observer(observer)
    log "Removing observer #{observer.addr} from #{addr}"

    observers.delete observer
  end

  def find_references
    if is_formula?
      formula.scan(ADDR_PATTERN_RE).uniq.map { |ref_addr| spreadsheet.get ref_addr }
    else
      []
    end
  end

  def sync_references
    current_references =  Set.new(find_references)

    references_to_remove = references - current_references
    references_to_add    = current_references - references

    references_to_remove.each { |reference| remove_reference reference }
    references_to_add.each { |reference| add_reference reference }
  end

  def notify_observers
    log "Notifying #{addr}'s observers #{observers.map(&:addr).inspect}"

    observers.each do |observer|
      observer.eval true
    end
  end

  # Recursive version.
  # def directly_or_indirectly_references?(cell)
  #   log "Checking if #{addr} directly or indirectly references #{cell.addr}"
  #
  #   self == cell || references.any? do |reference|
  #     reference.directly_or_indirectly_references? cell
  #   end
  # end

  # Non-recursive version.
  def directly_or_indirectly_references?(cell)
    log "Checking if #{addr} directly or indirectly references #{cell.addr}"

    references_visitor do |reference|
      return true if reference == cell
    end

    false
  end

  def references_visitor
    return enum_for(:references_visitor) unless block_given?

    index       = 0
    visited     = {}
    visit_queue = []

    # Start scheduling a visit for the node pointed to by 'self'.
    visit_queue << self

    # Repeat while there are still nodes to be visited.
    while !visit_queue.empty? do
      current = visit_queue.shift     # Retrieve the oldest key.

      # Visit the node and save the result.
      visited[current] = yield(current, index)

      # Schedule a visit for each of the current node's references.
      current.references.each do |reference|
        # But do it only if node has not yet been visited nor already marked for visit (in the visit queue).
        visit_queue << reference unless visit_queue.include?(reference) || visited.has_key?(reference)
      end

      index += 1
    end

    visited
  end

  def inspect
    [addr, content, { references: references.map(&:addr) }, { observers: observers.map(&:addr) }]
  end
end

def run!
  s = Spreadsheet.new

  a1 = s.set(:A1, 1)

  (2..100).each do |i|
    s.set :"A#{i}", "=A#{i-1}+1"
  end
end

run! if __FILE__ == $0
