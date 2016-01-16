# require 'pp'

DEBUG = true

class Spreadsheet
  attr_reader :cells

  def initialize
    @cells = {}
  end

  def set_cell(addr, content = nil)
    cells[addr] = Cell.new(self, addr, content)
  end

  def find_cell(addr)
    cells[addr] || set_cell(addr)
  end

  def consistent?
    true
  end
end

class Cell
  DEFAULT_VALUE = 0
  ADDR_PATTERN  = '[A-Z]+[1-9]\d*'

  attr_reader :spreadsheet, :addr, :content, :references, :observers

  def initialize(spreadsheet, addr, content)
    @spreadsheet = spreadsheet
    @addr        = addr
    @references  = []
    @observers   = []

    self.content = content
  end

  def content=(new_content)
    puts "Changing #{addr} from `#{content}` to `#{new_content}`"

    @content = new_content

    reset_references

    if is_formula?(new_content)
      # First implementation could be something like:
      #
      # @references = new_content.scan(Regexp.new(ADDR_PATTERN)).map do |ref_addr|
      #   spreadsheet.find_cell ref_addr.to_sym
      # end
      #
      # But would we update the observers list???

      new_content.scan(Regexp.new(ADDR_PATTERN, Regexp::IGNORECASE)).map do |ref_addr|
        add_reference spreadsheet.find_cell(ref_addr.to_sym)
      end
    end

    eval reevaluate: true
  end

  def eval(reevaluate: false)
    previous_evaluated_content = @evaluated_content

    @evaluated_content = nil if reevaluate

    @evaluated_content ||= begin
      puts "Evaluating #{addr}" if DEBUG

      new_value =
        if is_formula?
          evaluatable_content = content[1..-1].gsub(Regexp.new(ADDR_PATTERN)) do |ref_addr|
            spreadsheet.find_cell(ref_addr.to_sym).eval
          end

          Kernel.eval evaluatable_content

          # values = formula.scan(Regexp.new(ADDR_PATTERN, Regexp::IGNORECASE)).inject({}) do |memo, ref_addr|
          #   memo[ref_addr.to_sym] = spreadsheet.find_cell(ref_addr.to_sym).eval || DEFAULT_VALUE
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

    notify_observers if previous_evaluated_content != @evaluated_content

    new_value || DEFAULT_VALUE
  end

  protected

  def is_formula?(any_content = content)
    any_content.is_a?(String) && any_content.start_with?('=')
  end

  def formula
    content[1..-1] if is_formula?
  end

  def add_reference(reference)
    raise "Cyclical reference detected when adding #{reference.addr} to #{addr}" if reference.directly_or_indirectly_references?(self)

    puts "Adding reference #{reference.addr} to #{addr}" if DEBUG

    references << reference

    reference.add_observer self
  end

  def remove_reference(reference)
    puts "Removing reference #{reference.addr} from #{addr}" if DEBUG

    references.delete reference

    reference.remove_observer self
  end

  def add_observer(observer)
    puts "Adding observer #{observer.addr} to #{addr}" if DEBUG

    observers << observer
  end

  def remove_observer(observer)
    puts "Removing observer #{observer.addr} from #{addr}" if DEBUG

    observers.delete observer
  end

  def reset_references
    references.clone.each do |reference|
      remove_reference reference
    end
  end

  def notify_observers
    puts "Notifying #{addr}'s observers #{observers.map(&:addr).inspect}" if DEBUG

    observers.each do |observer|
      observer.eval reevaluate: true
    end
  end

  def directly_or_indirectly_references?(cell)
    self == cell || references.any? { |reference| reference.directly_or_indirectly_references?(cell) }
  end

  def inspect
    [addr, content, { references: references.map(&:addr) }, { observers: observers.map(&:addr) }]
  end
end

def run!
  s = Spreadsheet.new

  a1 = s.set_cell(:A1, 1)
  a2 = s.set_cell(:A2, 2)
  a3 = s.set_cell(:A3)
  a4 = s.set_cell(:A4, '=A1+A2+A3')
  a5 = s.set_cell(:A5, '=A4*2')
  # a1.content = '=A5'

  puts 'Initial spreadsheet:'
  p s
  p [a1, a2, a3, a4, a5].map { |cell| [cell.content, cell.eval] }

  puts 'Setting A1 to 10:'
  a1.content = 10
  p [a1, a2, a3, a4, a5].map { |cell| [cell.content, cell.eval] }

  puts 'Setting A2 to 20:'
  a2.content = 20
  p [a1, a2, a3, a4, a5].map { |cell| [cell.content, cell.eval] }

  puts 'Setting A3 to 30:'
  a3.content = 30
  p [a1, a2, a3, a4, a5].map { |cell| [cell.content, cell.eval] }

  puts 'Setting A4 to "=1+1":'
  a4.content = '=1+1'
  p [a1, a2, a3, a4, a5].map { |cell| [cell.content, cell.eval] }

  puts 'Final spreadsheet:'
  p s
end

run! if __FILE__ == $0
