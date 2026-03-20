class UserSchoolRole
    include Mongoid::Document
    include Mongoid::Timestamps
  
    # Fields to store the relationship
    field :user_id, type: BSON::ObjectId
    field :school_id, type: BSON::ObjectId
    field :role, type: String # The role of the user in the school
  
    # Validations
    validates :user_id, presence: true
    validates :school_id, presence: true
    validates :role, presence: true
  
    # Associations
    belongs_to :user, class_name: 'User', inverse_of: :user_school_roles
    belongs_to :school, class_name: 'School', inverse_of: :user_school_roles
  
    # Index for faster querying
    index({ user_id: 1, school_id: 1 }, { unique: true })
  
    # Scopes for easy retrieval of user roles in a school
    scope :by_user, ->(user_id) { where(user_id: user_id) }
    scope :by_school, ->(school_id) { where(school_id: school_id) }
    scope :by_role, ->(role) { where(role: role) }
  end
  