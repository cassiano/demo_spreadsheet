require_relative 'demo_spreadsheet'
require 'minitest/autorun'
require 'set'

describe Spreadsheet do
  # Runs codes before each expectation.
  before do
    @spreadsheet = Spreadsheet.new
  end

  # Runs code after each expectation.
  after do
    @spreadsheet.consistent?.must_equal true
  end

  it 'will be empty when created' do
    @spreadsheet.cell_count.must_equal 0
  end

  it 'allows cells to contain scalar values' do
    a1 = @spreadsheet.set(:A1, 1)
    a2 = @spreadsheet.set(:A2, 2)
    a3 = @spreadsheet.set(:A3)

    a1.eval.must_equal 1
    a2.eval.must_equal 2
    a3.eval.must_equal Cell::DEFAULT_VALUE
  end

  it 'allows cells to also contain formulas' do
    a1 = @spreadsheet.set(:A1, 1)
    a2 = @spreadsheet.set(:A2, 2)
    a3 = @spreadsheet.set(:A3)
    a4 = @spreadsheet.set(:A4, '=A1+A2+A3')
    a5 = @spreadsheet.set(:A5, '=A4*2')

    a4.eval.must_equal (a4_value = 1 + 2 + Cell::DEFAULT_VALUE)
    a5.eval.must_equal a4_value * 2
  end

  it 'allows cells to propagate their changes to other cells (in  a chain)' do
    a1 = @spreadsheet.set(:A1, 1)
    a2 = @spreadsheet.set(:A2, 2)
    a3 = @spreadsheet.set(:A3)
    a4 = @spreadsheet.set(:A4, '=A1+A2+A3')
    a5 = @spreadsheet.set(:A5, '=A4*2')

    a1.content = 10

    a4.eval.must_equal (a4_value = 10 + 2 + Cell::DEFAULT_VALUE)
    a5.eval.must_equal a4_value * 2

    a3.content = 30

    a4.eval.must_equal (a4_value = 10 + 2 + 30)
    a5.eval.must_equal a4_value * 2
  end

  describe 'cell references and observers' do
    it 'keeps these 2 collections for all cells' do
      a4 = @spreadsheet.set(:A4, '=A1+A2+A3')

      a1 = @spreadsheet.get(:A1)
      a2 = @spreadsheet.get(:A2)
      a3 = @spreadsheet.get(:A3)

      a4.references.size.must_equal 3
      a4.references.must_equal Set.new([a1, a2, a3])
      a4.observers.must_be_empty

      a1.references.must_be_empty
      a1.observers.must_equal Set.new([a4])

      a2.references.must_be_empty
      a2.observers.must_equal Set.new([a4])

      a3.references.must_be_empty
      a3.observers.must_equal Set.new([a4])
    end

    it 'keeps these collections always in sync' do
      a5 = @spreadsheet.set(:A5, '=A1+A2+A3')

      a5.content = '=A2+A4'

      a1 = @spreadsheet.get(:A1)
      a2 = @spreadsheet.get(:A2)
      a3 = @spreadsheet.get(:A3)
      a4 = @spreadsheet.get(:A4)

      a5.references.must_equal Set.new([a2, a4])
      a5.observers.must_be_empty

      a1.references.must_be_empty
      a1.observers.must_be_empty

      a2.references.must_be_empty
      a2.observers.must_equal Set.new([a5])

      a3.references.must_be_empty
      a3.observers.must_be_empty

      a4.references.must_be_empty
      a2.observers.must_equal Set.new([a5])
    end
  end

  describe "cyclical references" do
    it "checks for direct (auto) references" do
      -> { @spreadsheet.set(:A1, '=A1+1') }.must_raise Cell::CircularReferenceError
    end

    it "checks for indirect references" do
      -> {
        a1 = @spreadsheet.set(:A1, '=A2')
        a2 = @spreadsheet.set(:A2, '=A3')
        a3 = @spreadsheet.set(:A3, '=A1')
      }.must_raise Cell::CircularReferenceError
    end
  end
end
