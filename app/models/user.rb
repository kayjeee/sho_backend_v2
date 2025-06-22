class User
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== FIELDS ========================
  field :name,             type: String               # Full name of the user
  field :email,            type: String               # Unique email address
  field :auth0_id,         type: String               # Unique Auth0 identifier
  field :roles,            type: Array,  default: []   # Roles e.g. ["Admin", "Teacher"]
  field :cash_account,     type: Float,  default: 0.0  # User's cash balance
  field :payment_history,  type: Array,  default: []   # Historical payment records
  # The 'schools' array field defined here previously conflicted with has_and_belongs_to_many.
  # It has been removed. The association now handles school linking via `school_ids`.

  # ===================== VALIDATIONS ======================
  validates :email,        presence: true, uniqueness: true
  validates :auth0_id,     presence: true, uniqueness: true

  # ===================== ASSOCIATIONS =====================
  # A user can have many conversations.
  has_many :conversations,       foreign_key: :user_id
  # A user can have many financial accounts.
  has_many :accounts,            class_name: 'Account', inverse_of: :user
  # A user can send many messages.
  has_many :sent_messages,       class_name: 'Message', inverse_of: :sender
  # General association for messages where user is involved (e.g., as a participant).
  has_many :messages,            inverse_of: :user
  # A user can receive many messages.
  has_many :received_messages,   class_name: 'Message', inverse_of: :receiver
  # Association with UserSchoolRole as the join table for managing school-specific roles.
  has_many :user_school_roles,   class_name: 'UserSchoolRole', inverse_of: :user

  # Establishes a many-to-many relationship with the `School` model.
  # Mongoid automatically manages a `school_ids` array (containing BSON::ObjectId)
  # on the User document to maintain this association.
  # `validate: false` is used to skip validation of associated school objects
  # when the user object is saved, which can be useful for performance or
  # when schools might not be fully loaded.
  has_and_belongs_to_many :schools, class_name: 'School', inverse_of: :users, validate: false

  # ======================== CALLBACKS =======================
  # This callback logs changes to the `school_ids` array, which is implicitly managed
  # by the `has_and_belongs_to_many :schools` association.
  before_save :log_school_id_changes, if: :school_ids_changed?

  # ========================= METHODS ========================

  # Purpose: Adds a school to the user's associated schools via the `has_and_belongs_to_many` association.
  # This method finds the `School` document by its ID and adds the object to the association.
  #
  # @param school_id_string [String] The string representation of the school's BSON::ObjectId to add.
  # @return [Boolean] True if the school was successfully associated or already was, false otherwise.
  def add_school(school_id_string)
    Rails.logger.debug "🏫 User#add_school: Attempting to add school with ID string '#{school_id_string}' to user #{id}"

    # Validate and convert the school_id_string to a BSON::ObjectId
    begin
      school_bson_id = BSON::ObjectId.from_string(school_id_string.to_s.strip)
    rescue BSON::ObjectId::Invalid
      Rails.logger.error "❌ User#add_school: Invalid BSON::ObjectId string provided: '#{school_id_string}'."
      errors.add(:schools, "Invalid school ID format.")
      return false
    end

    # Find the School document by its BSON::ObjectId.
    school_to_add = School.find_by(_id: school_bson_id)

    unless school_to_add
      Rails.logger.warn "⚠️ User#add_school: School with ID '#{school_id_string}' not found in database. Cannot associate."
      errors.add(:schools, "School not found.")
      return false
    end

    # Check if the school is already associated with this user.
    # The `include?` method on a `has_and_belongs_to_many` association checks for the actual object.
    if self.schools.include?(school_to_add)
      Rails.logger.info "✅ User#add_school: School '#{school_id_string}' is already associated with user #{id}. No action taken."
      return true # It's already there, so consider it a success.
    end

    # Add the found School object to the `schools` association.
    # This automatically updates the `school_ids` array internally.
    self.schools << school_to_add

    # Attempt to save the User document to persist the association change.
    if save
      Rails.logger.info "✅ User#add_school: Successfully associated school '#{school_id_string}' with user #{id}."
      true
    else
      Rails.logger.error "❌ User#add_school: Failed to save user #{id} after associating school '#{school_id_string}'. Errors: #{errors.full_messages.join(', ')}"
      false
    end
  end

  # Purpose: Removes a school from the user's associated schools.
  # This method finds the `School` document by its ID and removes the object from the association.
  #
  # @param school_id_string [String] The string representation of the school's BSON::ObjectId to remove.
  # @return [Boolean] True if removed and saved, false if not found or save fails.
  def remove_school(school_id_string)
    Rails.logger.debug "➖ User#remove_school: Attempting to remove school with ID string '#{school_id_string}' from user #{id}"

    begin
      school_bson_id = BSON::ObjectId.from_string(school_id_string.to_s.strip)
    rescue BSON::ObjectId::Invalid
      Rails.logger.error "❌ User#remove_school: Invalid BSON::ObjectId string provided: '#{school_id_string}'."
      errors.add(:schools, "Invalid school ID format.")
      return false
    end

    school_to_remove = self.schools.find_by(_id: school_bson_id)

    unless school_to_remove
      Rails.logger.warn "⚠️ User#remove_school: School with ID '#{school_id_string}' not found in user's associations for user #{id}."
      return false
    end

    # Remove the school object from the association.
    # This automatically updates the `school_ids` array internally.
    self.schools.delete(school_to_remove)

    if save
      Rails.logger.info "🗑️ User#remove_school: Successfully removed school '#{school_id_string}' from user #{id}."
      true
    else
      Rails.logger.error "❌ User#remove_school: Failed to save user #{id} after removing school '#{school_id_string}'. Errors: #{errors.full_messages.join(', ')}"
      false
    end
  end

  private

  # Purpose: Logs changes to the `school_ids` array, which is implicitly managed by Mongoid
  # for the `has_and_belongs_to_many` association.
  # This provides detailed insight into which schools are added or removed from a user's associations.
  def log_school_id_changes
    # `changes_to_save` provides a hash of fields that are about to be saved,
    # with keys as field names and values as [old_value, new_value].
    # We are interested in the 'school_ids' field implicitly created by the HABTM association.
    old_school_ids, new_school_ids = changes_to_save['school_ids']

    # Initialize with empty arrays if values are nil to prevent errors in set operations.
    old_school_ids = old_school_ids || []
    new_school_ids = new_school_ids || []

    # Convert BSON::ObjectIds to strings for logging clarity.
    old_school_ids_str = old_school_ids.map(&:to_s)
    new_school_ids_str = new_school_ids.map(&:to_s)

    # Calculate added and removed school IDs using set difference.
    added   = new_school_ids_str - old_school_ids_str
    removed = old_school_ids_str - new_school_ids_str

    Rails.logger.debug "🔄 User#log_school_id_changes: Associated schools updated for user #{id}:"
    Rails.logger.debug "  OLD (IDs): #{old_school_ids_str.inspect}"
    Rails.logger.debug "  NEW (IDs): #{new_school_ids_str.inspect}"
    Rails.logger.debug "  ➕ ADDED (IDs): #{added.inspect}"   if added.any?
    Rails.logger.debug "  ➖ REMOVED (IDs): #{removed.inspect}" if removed.any?
  end
end