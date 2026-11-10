# frozen_string_literal: true

class Order
  include Mongoid::Document
  include Mongoid::Timestamps

  STATUSES = %w[placed accepted preparing ready completed cancelled rejected].freeze
  ALLOWED_TRANSITIONS = {
    "placed" => %w[accepted rejected cancelled],
    "accepted" => %w[preparing cancelled],
    "preparing" => %w[ready],
    "ready" => %w[completed],
    "completed" => [],
    "cancelled" => [],
    "rejected" => []
  }.freeze

  # Associations
  belongs_to :school, class_name: "School", foreign_key: :school_id
  belongs_to :user, class_name: "User", foreign_key: :user_id

  # Embedded Order Items
  embeds_many :items, class_name: "OrderItem"
  accepts_nested_attributes_for :items

  # Fields
  field :learner_id, type: String # Optional
  field :order_number, type: String # Unique SHO-YYMMDD-XXXX
  field :status, type: String, default: "placed"
  field :fulfilment_method, type: String, default: "collect"
  field :notes, type: String
  field :subtotal_cents, type: Integer, default: 0
  field :currency, type: String, default: "ZAR"
  field :payment_status, type: String, default: "unpaid"
  field :status_history, type: Array, default: [] # Array of { status, at, by }
  field :placed_at, type: DateTime

  # Validations
  validates :order_number, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :fulfilment_method, presence: true, inclusion: { in: %w[collect] }
  validates :subtotal_cents, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :currency, presence: true
  validate :enforce_status_transition, on: :update, if: :status_changed?

  # Indexes
  index({ school_id: 1, status: 1, created_at: -1 })
  index({ user_id: 1, created_at: -1 })
  index({ order_number: 1 }, { unique: true })

  # Callbacks
  before_validation :generate_order_number, on: :create
  before_create :set_initial_placed_at_and_history

  # Scopes
  scope :by_school, ->(school_id) { where(school_id: school_id) }
  scope :by_user, ->(user_id) { where(user_id: user_id) }
  scope :by_status, ->(status) { where(status: status) }
  scope :recent, -> { order(created_at: :desc) }

  # Status transition methods
  def can_transition_to?(new_status)
    allowed = ALLOWED_TRANSITIONS[status] || []
    allowed.include?(new_status.to_s)
  end

  def transition_to!(new_status, by_user_id: nil)
    unless can_transition_to?(new_status)
      errors.add(:status, "cannot transition from #{status} to #{new_status}")
      return false
    end

    self.status = new_status
    self.status_history = (status_history || []) + [ {
      status: new_status,
      at: Time.current.iso8601,
      by: by_user_id.to_s.presence
    } ]

    saved = save
    if saved && %w[cancelled rejected].include?(new_status)
      restore_items_stock!
    end
    saved
  end

  def cancel_by_parent!(parent_user_id)
    unless status == "placed"
      errors.add(:status, "orders can only be cancelled while in placed status")
      return false
    end

    transition_to!("cancelled", by_user_id: parent_user_id)
  end

  def restore_items_stock!
    items.each do |item|
      CatalogItem.atomic_increment_stock!(
        item.catalog_item_id,
        variant_label: item.variant_label,
        quantity: item.quantity
      )
    end
  end

  def calculate_subtotal_cents!
    self.subtotal_cents = items.sum(&:total_price_cents)
  end

  def to_api_hash
    {
      id: id.to_s,
      order_number: order_number,
      school_id: school_id.to_s,
      user_id: user_id.to_s,
      learner_id: learner_id,
      status: status,
      fulfilment_method: fulfilment_method,
      notes: notes,
      subtotal_cents: subtotal_cents,
      currency: currency,
      payment_status: payment_status,
      placed_at: placed_at,
      status_history: status_history || [],
      items: items.map(&:as_json),
      created_at: created_at,
      updated_at: updated_at
    }
  end

  def as_json(options = {})
    to_api_hash
  end

  private

  def enforce_status_transition
    old_status = status_was || status
    allowed = ALLOWED_TRANSITIONS[old_status] || []
    unless allowed.include?(status)
      errors.add(:status, "cannot transition from '#{old_status}' to '#{status}'. Allowed: #{allowed.join(', ')}")
    end
  end

  def generate_order_number
    return if order_number.present?

    date_str = Time.current.strftime("%y%m%d")
    loop do
      random_code = SecureRandom.alphanumeric(4).upcase
      candidate = "SHO-#{date_str}-#{random_code}"
      unless self.class.where(order_number: candidate).exists?
        self.order_number = candidate
        break
      end
    end
  end

  def set_initial_placed_at_and_history
    self.placed_at ||= Time.current
    if status_history.blank?
      self.status_history = [ {
        status: status || "placed",
        at: Time.current.iso8601,
        by: user_id.to_s.presence
      } ]
    end
  end
end
