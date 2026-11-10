# frozen_string_literal: true

class CatalogVariant
  include Mongoid::Document

  embedded_in :catalog_item

  field :label, type: String # e.g. "S", "M", "L", "Blue", "Pack of 3"
  field :price_cents, type: Integer # Override price; nil means use parent CatalogItem price
  field :stock_quantity, type: Integer # nil = unlimited, otherwise non-negative integer

  validates :label, presence: true
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :stock_quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  def in_stock?(requested_quantity = 1)
    return true if stock_quantity.nil?

    stock_quantity >= requested_quantity
  end

  def as_json(options = {})
    {
      id: id.to_s,
      label: label,
      price_cents: price_cents,
      stock_quantity: stock_quantity,
      in_stock: in_stock?
    }
  end
end
