# frozen_string_literal: true

class OrderItem
  include Mongoid::Document

  embedded_in :order

  # References
  field :catalog_item_id, type: String

  # Snapshots at the time of order placement
  field :name_snapshot, type: String
  field :category_snapshot, type: String
  field :unit_price_cents, type: Integer
  field :quantity, type: Integer, default: 1
  field :variant_label, type: String
  field :options, type: Hash, default: {} # e.g. { color: true, double_sided: false, copies: 1 }

  # Validations
  validates :catalog_item_id, presence: true
  validates :name_snapshot, presence: true
  validates :unit_price_cents, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :quantity, presence: true, numericality: { only_integer: true, greater_than: 0 }

  def total_price_cents
    unit_price_cents * quantity
  end

  def as_json(options = {})
    {
      id: id.to_s,
      catalog_item_id: catalog_item_id,
      name: name_snapshot,
      category: category_snapshot,
      unit_price_cents: unit_price_cents,
      quantity: quantity,
      variant_label: variant_label,
      options: options || {},
      total_price_cents: total_price_cents
    }
  end
end
