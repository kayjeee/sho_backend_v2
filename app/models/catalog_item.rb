# frozen_string_literal: true

class CatalogItem
  include Mongoid::Document
  include Mongoid::Timestamps

  CATEGORIES = %w[print stationery uniform].freeze

  # Associations
  belongs_to :school, class_name: "School", foreign_key: :school_id

  # Embedded variants (sizes, colors, packages, etc.)
  embeds_many :variants, class_name: "CatalogVariant"
  accepts_nested_attributes_for :variants, allow_destroy: true

  # Fields
  field :name, type: String
  field :description, type: String
  field :category, type: String # enum: print | stationery | uniform
  field :subcategory, type: String # free text: past_exam_paper, assignment, pens, blazer, etc.
  field :price_cents, type: Integer # stored as integer cents
  field :currency, type: String, default: "ZAR"
  field :image_url, type: String
  field :is_active, type: Boolean, default: true
  field :stock_quantity, type: Integer # nil = unlimited
  field :grade_ids, type: Array, default: [] # empty array = available to all grades
  field :subject, type: String
  field :academic_year, type: String
  field :tags, type: Array, default: []
  field :position, type: Integer, default: 0
  field :print_options, type: Hash, default: {} # { color_allowed: bool, double_sided_allowed: bool, max_copies: int }
  field :file_url, type: String # document/file URL for print jobs

  # Validations
  validates :name, presence: true
  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validates :price_cents, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :currency, presence: true
  validates :stock_quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  # Indexes
  index({ school_id: 1, category: 1, is_active: 1 })
  index({ school_id: 1, is_active: 1 })

  # Scopes
  scope :active, -> { where(is_active: true) }
  scope :by_school, ->(school_id) { where(school_id: school_id) }
  scope :by_category, ->(cat) { where(category: cat) }
  scope :in_stock, -> { any_of({ stock_quantity: nil }, { :stock_quantity.gt => 0 }) }

  # Checks if item is in stock for a variant and requested quantity
  def in_stock?(variant_label: nil, quantity: 1)
    if variant_label.present?
      variant = find_variant(variant_label)
      return false unless variant

      return variant.in_stock?(quantity)
    end

    return true if stock_quantity.nil?

    stock_quantity >= quantity
  end

  def find_variant(label)
    return nil if label.blank?

    variants.where(label: label).first || variants.detect { |v| v.label.to_s.casecmp(label.to_s).zero? }
  end

  def effective_price_cents(variant_label = nil)
    if variant_label.present?
      variant = find_variant(variant_label)
      return variant.price_cents if variant&.price_cents.present?
    end

    price_cents
  end

  def available_for_grade?(grade_id)
    return true if grade_ids.blank?
    return false if grade_id.blank?

    grade_ids.map(&:to_s).include?(grade_id.to_s)
  end

  # Atomic decrement stock for an item or variant
  # Returns true on success, false if insufficient stock
  def self.atomic_decrement_stock!(item_id, variant_label: nil, quantity: 1)
    return true if quantity <= 0

    bson_id = item_id.is_a?(BSON::ObjectId) ? item_id : BSON::ObjectId.from_string(item_id.to_s)

    if variant_label.present?
      # Case 1: Variant with unlimited stock (stock_quantity == nil)
      doc_unlimited = collection.find_one_and_update(
        {
          "_id" => bson_id,
          "variants" => {
            "$elemMatch" => {
              "label" => variant_label,
              "stock_quantity" => nil
            }
          }
        },
        { "$set" => { "updated_at" => Time.current.utc } },
        return_document: :after
      )
      return true if doc_unlimited

      # Case 2: Variant with numeric stock
      doc_numeric = collection.find_one_and_update(
        {
          "_id" => bson_id,
          "variants" => {
            "$elemMatch" => {
              "label" => variant_label,
              "stock_quantity" => { "$gte" => quantity }
            }
          }
        },
        {
          "$inc" => { "variants.$.stock_quantity" => -quantity },
          "$set" => { "updated_at" => Time.current.utc }
        },
        return_document: :after
      )
      !doc_numeric.nil?
    else
      # Item without variant: unlimited stock
      doc_unlimited = collection.find_one_and_update(
        { "_id" => bson_id, "stock_quantity" => nil },
        { "$set" => { "updated_at" => Time.current.utc } },
        return_document: :after
      )
      return true if doc_unlimited

      # Item without variant: numeric stock
      doc_numeric = collection.find_one_and_update(
        { "_id" => bson_id, "stock_quantity" => { "$gte" => quantity } },
        {
          "$inc" => { "stock_quantity" => -quantity },
          "$set" => { "updated_at" => Time.current.utc }
        },
        return_document: :after
      )
      !doc_numeric.nil?
    end
  rescue BSON::Error::InvalidObjectId
    false
  end

  # Atomic increment / restore stock
  def self.atomic_increment_stock!(item_id, variant_label: nil, quantity: 1)
    return true if quantity <= 0

    bson_id = item_id.is_a?(BSON::ObjectId) ? item_id : BSON::ObjectId.from_string(item_id.to_s)

    if variant_label.present?
      collection.find_one_and_update(
        {
          "_id" => bson_id,
          "variants" => {
            "$elemMatch" => {
              "label" => variant_label,
              "stock_quantity" => { "$ne" => nil }
            }
          }
        },
        {
          "$inc" => { "variants.$.stock_quantity" => quantity },
          "$set" => { "updated_at" => Time.current.utc }
        }
      )
    else
      collection.find_one_and_update(
        { "_id" => bson_id, "stock_quantity" => { "$ne" => nil } },
        {
          "$inc" => { "stock_quantity" => quantity },
          "$set" => { "updated_at" => Time.current.utc }
        }
      )
    end
    true
  rescue BSON::Error::InvalidObjectId
    false
  end

  def to_api_hash
    {
      id: id.to_s,
      school_id: school_id.to_s,
      name: name,
      description: description,
      category: category,
      subcategory: subcategory,
      price_cents: price_cents,
      currency: currency,
      image_url: image_url,
      is_active: is_active,
      stock_quantity: stock_quantity,
      in_stock: in_stock?,
      grade_ids: grade_ids || [],
      subject: subject,
      academic_year: academic_year,
      tags: tags || [],
      position: position,
      print_options: print_options || {},
      file_url: file_url,
      variants: variants.map(&:as_json),
      created_at: created_at,
      updated_at: updated_at
    }
  end

  def as_json(options = {})
    to_api_hash
  end
end
