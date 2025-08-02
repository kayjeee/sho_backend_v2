# app/services/learner_services/bulk_upload_service.rb
module LearnerServices
  class BulkUploadService
    def self.call(school:, current_user:, learner_data:, grade_id: nil)
      new(school, current_user, learner_data, grade_id).call
    end

    def initialize(school, current_user, learner_data, grade_id)
      @school = school
      @current_user = current_user
      @learner_data = learner_data || []
      @grade_id = grade_id
      @inserted_count = 0
      @duplicates_count = 0
      @errors = []
    end

    def call
      validate_input
      process_learners unless @errors.any?

      self
    end

    def success?
      @errors.empty? && @inserted_count.positive?
    end

    def inserted_count
      @inserted_count
    end

    def duplicates_count
      @duplicates_count
    end

    def errors
      @errors
    end

    def message
      if success?
        "Successfully uploaded #{@inserted_count} learners"
      elsif @errors.any?
        "Upload completed with #{@errors.size} errors"
      else
        "No learners were uploaded"
      end
    end

    private

    def validate_input
      if @learner_data.empty?
        @errors << { type: :empty_data, message: "No learner data provided" }
      elsif !@learner_data.is_a?(Array)
        @errors << { type: :invalid_format, message: "Learner data must be an array" }
      end
    end

    def process_learners
      ActiveRecord::Base.transaction do
        @learner_data.each_with_index do |learner_params, index|
          process_learner(learner_params, index + 1)
        end
      end
    rescue StandardError => e
      @errors << { type: :processing_error, message: "System error: #{e.message}" }
      raise ActiveRecord::Rollback
    end

    def process_learner(params, row_number)
      # Normalize and prepare learner attributes
      attributes = prepare_learner_attributes(params)

      # Check for duplicates based on first name, last name, and school
      if duplicate_learner?(attributes)
        @duplicates_count += 1
        return
      end

      learner = @school.learners.new(attributes)
      learner.created_by = @current_user

      if learner.save
        @inserted_count += 1
      else
        @errors << {
          row: row_number,
          message: learner.errors.full_messages.join(', '),
          details: learner.attributes
        }
      end
    end

    def prepare_learner_attributes(params)
      {
        first_name: params[:firstName].to_s.strip,
        last_name: params[:lastName].to_s.strip,
        gender: normalize_gender(params[:gender]),
        phone: normalize_phone(params[:phone]),
        whatsapp: normalize_phone(params[:whatsapp]),
        telegram: params[:telegram].to_s.strip,
        accession_number: params[:accessionNumber].presence || generate_accession_number,
        grade_id: @grade_id,
        status: 'active'
      }.compact
    end

    def duplicate_learner?(attributes)
      @school.learners.exists?(
        first_name: attributes[:first_name],
        last_name: attributes[:last_name]
      )
    end

    def normalize_gender(gender)
      return nil if gender.blank?
      
      case gender.to_s.downcase
      when 'm', 'male' then 'male'
      when 'f', 'female' then 'female'
      else 'other'
      end
    end

    def normalize_phone(phone)
      return nil if phone.blank?
      phone.to_s.gsub(/[^0-9+]/, '')
    end

    def generate_accession_number
      # Implement your own logic for generating student IDs
      "STD#{Time.now.to_i.to_s.last(6)}#{rand(100..999)}"
    end
  end
end