class PrCodeTemplate
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name, type: String
  field :description, type: String
  field :channels, type: Array, default: [] # e.g., ['whatsapp', 'sms', 'email']
  field :subject, type: String
  field :content, type: String
  field :variables, type: Array, default: []
  field :is_default, type: Boolean, default: false
  
  belongs_to :school, optional: true

  validates :name, :content, presence: true
  validates :channels, presence: true
  
  before_save :extract_variables

  private

  def extract_variables
    # Extracts variables like {{variable_name}} from subject and content
    self.variables = (subject.to_s.scan(/\{\{(\w+)\}\}/).flatten + 
                      content.to_s.scan(/\{\{(\w+)\}\}/).flatten).uniq
  end
end
