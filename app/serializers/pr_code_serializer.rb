# app/serializers/pr_code_serializer.rb
class PrCodeSerializer
  include JSONAPI::Serializer
  include ActionView::Helpers::DateHelper  # enables distance_of_time_in_words

  attributes :code, :purpose, :status, :metadata, :expires_at, :used_at, :created_at

  attribute :is_expired do |object|
    object.expired?
  end

  attribute :time_remaining do |object|
    if object.expires_at.present? && object.expires_at.future?
      ActionController::Base.helpers.distance_of_time_in_words(Time.current, object.expires_at)
    else
      'expired'
    end
  end

  belongs_to :school
  belongs_to :user
end
