# frozen_string_literal: true

require "test_helper"

class CatalogItemTest < ActiveSupport::TestCase
  def setup
    @school = School.create!(schoolName: "Catalog School #{SecureRandom.hex(4)}", schoolEmail: "school_#{SecureRandom.hex(4)}@test.com")
  end

  def teardown
    @school&.destroy
    CatalogItem.where(school_id: @school.id.to_s).destroy_all if @school
  end

  test "validates presence of name and category" do
    item = CatalogItem.new(school_id: @school.id.to_s)
    assert_not item.valid?
    assert_includes item.errors[:name], "can't be blank"
    assert_includes item.errors[:category], "can't be blank"
  end

  test "validates category inclusion" do
    item = CatalogItem.new(school_id: @school.id.to_s, name: "Item", category: "invalid", price_cents: 100)
    assert_not item.valid?
    assert_includes item.errors[:category], "is not included in the list"

    item.category = "print"
    assert item.valid?
  end

  test "validates price_cents is non-negative integer" do
    item = CatalogItem.new(school_id: @school.id.to_s, name: "Item", category: "stationery", price_cents: -50)
    assert_not item.valid?
    assert_includes item.errors[:price_cents], "must be greater than or equal to 0"
  end

  test "atomic stock decrement and rollback" do
    item = CatalogItem.create!(
      school_id: @school.id.to_s,
      name: "Pencil",
      category: "stationery",
      price_cents: 1500,
      stock_quantity: 5
    )

    # Decrement 3
    assert CatalogItem.atomic_decrement_stock!(item.id, quantity: 3)
    item.reload
    assert_equal 2, item.stock_quantity

    # Decrement 3 when only 2 available -> fails
    assert_not CatalogItem.atomic_decrement_stock!(item.id, quantity: 3)
    item.reload
    assert_equal 2, item.stock_quantity

    # Restore stock
    assert CatalogItem.atomic_increment_stock!(item.id, quantity: 3)
    item.reload
    assert_equal 5, item.stock_quantity
  end

  test "variants effective price and stock" do
    item = CatalogItem.new(
      school_id: @school.id.to_s,
      name: "School Blazer",
      category: "uniform",
      price_cents: 50000
    )
    item.variants.build(label: "S", price_cents: 48000, stock_quantity: 3)
    item.variants.build(label: "M", price_cents: 50000, stock_quantity: 0)
    item.variants.build(label: "L", price_cents: nil, stock_quantity: nil)
    item.save!

    assert_equal 48000, item.effective_price_cents("S")
    assert_equal 50000, item.effective_price_cents("L") # falls back to parent price
    assert item.in_stock?(variant_label: "S", quantity: 2)
    assert_not item.in_stock?(variant_label: "M", quantity: 1)
    assert item.in_stock?(variant_label: "L", quantity: 99) # unlimited
  end
end
