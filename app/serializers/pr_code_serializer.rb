# app/serializers/pr_code_serializer.rb
class PrCodeSerializer < ActiveModel::Serializer
  attributes :id, :code, :purpose, :status, :metadata, :expires_at, :used_at, :created_at, :is_expired, :time_remaining

  belongs_to :school
  belongs_to :user

  def is_expired
    object.expired?
  end

  def time_remaining
    if object.expires_at > Time.current
      distance_of_time_in_words(Time.current, object.expires_at)
    else
      'expired'
    end
  end
end