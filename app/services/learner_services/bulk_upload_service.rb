# app/services/learner_services/bulk_upload_service.rb
module LearnerServices
  class BulkUploadService
    require 'csv'
    require 'roo'

    attr_reader :school_id, :file, :user, :errors, :processed_count, :imported_count

    def initialize(school_id:, file:, user:)
      @school_id = school_id
      @file = file
      @user = user
      @errors = []
      @processed_count = 0
      @imported_count = 0
    end

    def call
      Rails.logger.info "📥 Starting bulk learner upload for school_id=#{school_id} by user=#{user.id}"

      learners_data = parse_file
      return self if learners_data.empty?

      process_learners(learners_data)

      if success?
        Rails.logger.info "✅ Bulk upload completed successfully: #{imported_count}/#{processed_count} learners imported for school_id=#{school_id}"

        # Mark onboarding step complete
        OnboardingStatusService.mark_upload_learners_complete(user, {
          batch_size: imported_count,
          school_id: school_id
        })
      else
        Rails.logger.warn "⚠️ Bulk upload completed with errors: #{errors.count} issues found"
      end

      self
    rescue => e
      Rails.logger.error "❌ Bulk upload failed for school_id=#{school_id}: #{e.message}"
      if Rails.env.development?
        cleaned_trace = BacktraceCleanerUtil.clean(e.backtrace)
        Rails.logger.error cleaned_trace.join("\n")
      end
      errors << "Unexpected error: #{e.message}"
      self
    end

    def success?
      @errors.empty?
    end

    private

    # ================================
    # STEP 1: Parse File
    # ================================
    def parse_file
      extension = File.extname(file.original_filename).downcase
      Rails.logger.info "📂 Parsing file: #{file.original_filename} (#{extension})"

      case extension
      when '.csv'
        parse_csv(file)
      when '.xlsx', '.xls'
        parse_excel(file)
      else
        errors << "Unsupported file format: #{extension}"
        []
      end
    end

    def parse_csv(file)
      learners = []
      CSV.foreach(file.path, headers: true) do |row|
        learners << sanitize_row(row.to_h)
      end
      learners
    rescue => e
      errors << "Failed to parse CSV: #{e.message}"
      []
    end

    def parse_excel(file)
      spreadsheet = Roo::Spreadsheet.open(file.path)
      headers = spreadsheet.row(1).map(&:to_s)
      learners = []

      (2..spreadsheet.last_row).each do |i|
        row_data = Hash[[headers, spreadsheet.row(i)].transpose]
        learners << sanitize_row(row_data)
      end

      learners
    rescue => e
      errors << "Failed to parse Excel file: #{e.message}"
      []
    end

    # ================================
    # STEP 2: Validate & Process
    # ================================
    def sanitize_row(row)
      row.transform_keys! { |k| k.to_s.strip.downcase }
      {
        name: row['name']&.strip,
        grade: row['grade']&.strip,
        class_name: row['class']&.strip,
        parent_email: row['parent_email']&.strip&.downcase,
        parent_phone: row['parent_phone']&.strip,
        school_id: school_id
      }.compact
    end

    def process_learners(learners_data)
      @processed_count = learners_data.size
      valid_learners = []

      learners_data.each_with_index do |learner, index|
        if valid_learner?(learner)
          valid_learners << learner
        else
          errors << "Row #{index + 2}: Missing required fields (#{learner.inspect})"
        end
      end

      insert_learners(valid_learners)
    end

    def valid_learner?(learner)
      learner[:name].present? && learner[:grade].present?
    end

    # ================================
    # STEP 3: Bulk Insert
    # ================================
    def insert_learners(valid_learners)
      return if valid_learners.empty?

      collection = Mongoid.default_client[:learners]
      docs = valid_learners.map do |learner|
        {
          name: learner[:name],
          grade: learner[:grade],
          class_name: learner[:class_name],
          parent_email: learner[:parent_email],
          parent_phone: learner[:parent_phone],
          school_id: BSON::ObjectId.from_string(school_id),
          created_by: user.id,
          created_at: Time.current,
          updated_at: Time.current
        }
      end

      result = collection.insert_many(docs)
      @imported_count = result.inserted_count

      Rails.logger.info "📊 Inserted #{@imported_count} learners into MongoDB"
    rescue => e
      errors << "Database insert failed: #{e.message}"
    end
  end
end
