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

  def get(addr)
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

    reset_references

    if is_formula?
      formula.scan(ADDR_PATTERN_RE).uniq.map do |ref_addr|
        add_reference spreadsheet.get(ref_addr)
      end
    end

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

  def reset_references
    references.clone.each do |reference|
      remove_reference reference
    end
  end

  def notify_observers
    log "Notifying #{addr}'s observers #{observers.map(&:addr).inspect}"

    observers.each do |observer|
      observer.eval true
    end
  end

  def directly_or_indirectly_references?(cell)
    log "Checking if #{addr} directly or indirectly references #{cell.addr}"

    self == cell || references.any? do |reference|
      reference.directly_or_indirectly_references? cell
    end
  end

  def inspect
    [addr, content, { references: references.map(&:addr) }, { observers: observers.map(&:addr) }]
  end
end

# def run!
#   s = Spreadsheet.new
#
#   a1 = s.set(:A1, 1)
#   a2 = s.set(:A2, 2)
#   a3 = s.set(:A3)
#   a4 = s.set(:A4, '=A1+A2+A3')
#   a5 = s.set(:A5, '=A4*2')
#   # a1.content = '=A5'
#
#   puts 'Initial spreadsheet:'
#   p s
#   p [a1, a2, a3, a4, a5].map { |cell| [cell.content, cell.eval] }
#
#   puts 'Setting A1 to 10:'
#   a1.content = 10
#   p [a1, a2, a3, a4, a5].map { |cell| [cell.content, cell.eval] }
#
#   puts 'Setting A2 to 20:'
#   a2.content = 20
#   p [a1, a2, a3, a4, a5].map { |cell| [cell.content, cell.eval] }
#
#   puts 'Setting A3 to 30:'
#   a3.content = 30
#   p [a1, a2, a3, a4, a5].map { |cell| [cell.content, cell.eval] }
#
#   puts 'Setting A4 to "=1+1":'
#   a4.content = '=1+1'
#   p [a1, a2, a3, a4, a5].map { |cell| [cell.content, cell.eval] }
#
#   puts 'Final spreadsheet:'
#   p s
# end
#
# run! if __FILE__ == $0
