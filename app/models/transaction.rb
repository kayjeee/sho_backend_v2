class Transaction
    include Mongoid::Document
    include Mongoid::Timestamps
  
    # Fields
    field :user_id, type: String
    field :school_id, type: String
    field :amount, type: Float
    field :status, type: String, default: 'pending' # Can be 'pending', 'completed', 'failed'
    field :payment_gateway_response, type: Hash # Store payment gateway response for auditing
  
    # Validations
    validates :user_id, presence: true
    validates :school_id, presence: true
    validates :amount, presence: true, numericality: { greater_than: 0 }
  
    # Callbacks
    after_save :update_user_and_school_accounts
  
    private
  
    def update_user_and_school_accounts
      if status == 'completed'
        user = User.find(user_id)
        school = School.find(school_id)
  
        # Deduct amount from user's cash account
        user.update(cash_account: user.cash_account - amount)
  
        # Add amount to school's cash account
        school.update(cash_account: school.cash_account + amount)
  
        # Add transaction to user's and school's payment history
        user.payment_history << { transaction_id: id, amount: amount, date: created_at }
        school.payment_history << { transaction_id: id, amount: amount, date: created_at }
  
        user.save
        school.save
      end
    end
  end