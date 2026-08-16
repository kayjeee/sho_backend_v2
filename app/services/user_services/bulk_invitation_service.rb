# app/services/user_services/bulk_invitation_service.rb
module UserServices
  class BulkInvitationService
    ServiceResult = Struct.new(:success, :errors, :invitations, :stats, keyword_init: true)

    BATCH_SIZE = 500 # MongoDB optimal batch size

    def initialize(
      sender:,
      invitations_data:, # Array of invitation hashes
      role: 'parent',
      school_id:,
      invited_via: 'whatsapp'
    )
      @sender = sender
      @invitations_data = Array(invitations_data)
      @role = role
      @school_id = school_id.to_s
      @invited_via = invited_via

      @errors = []
      @successful_count = 0
      @failed_count = 0
      @failed_invitations = []
      @created_invitations = []
    end

    # ------------------------------------------------------------
    # ENTRY POINT
    # ------------------------------------------------------------
    def call
      return ServiceResult.new(
        success: false,
        errors: ["No invitations provided"]
      ) if @invitations_data.empty?

      Rails.logger.info "📦 Starting bulk invitation creation for #{@invitations_data.size} invitations"
      start_time = Time.current

      @invitations_data.each_slice(BATCH_SIZE).with_index do |batch, batch_index|
        process_batch(batch, batch_index)
      end

      elapsed_time = Time.current - start_time

      Rails.logger.info "✅ Bulk invitation completed in #{elapsed_time.round(2)}s"
      Rails.logger.info "   Successful: #{@successful_count}, Failed: #{@failed_count}"

      ServiceResult.new(
        success: @failed_count.zero?,
        errors: @errors,
        invitations: @created_invitations,
        stats: {
          total: @invitations_data.size,
          successful: @successful_count,
          failed: @failed_count,
          failed_invitations: @failed_invitations,
          elapsed_time: elapsed_time.round(2)
        }
      )
    rescue => e
      Rails.logger.error "❌ Bulk invitation service error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")

      ServiceResult.new(
        success: false,
        errors: [e.message],
        invitations: @created_invitations || [],
        stats: {
          total: @invitations_data.size,
          successful: @successful_count,
          failed: @failed_count
        }
      )
    end

    private

    # ------------------------------------------------------------
    # BATCH PROCESSING
    # ------------------------------------------------------------
    def process_batch(batch, batch_index)
      Rails.logger.info "🔄 Processing batch #{batch_index + 1} (#{batch.size} invitations)"

      valid_documents = []

      batch.each_with_index do |invitation_data, index|
        result = prepare_invitation(invitation_data, batch_index, index)

        if result[:valid]
          valid_documents << result[:document]
        else
          @failed_count += 1
          @failed_invitations << {
            data: invitation_data,
            errors: result[:errors]
          }
        end
      end

      insert_batch(valid_documents) if valid_documents.any?
    end

    # ------------------------------------------------------------
    # INVITATION PREP
    # ------------------------------------------------------------
    def prepare_invitation(data, batch_index, index)
      populate_learner_numbers!(data)

      errors = validate_invitation_data(data)

      if errors.any?
        Rails.logger.warn "⚠️ Invalid invitation at batch #{batch_index}, index #{index}: #{errors}"
        return { valid: false, errors: errors }
      end

      {
        valid: true,
        document: build_invitation_document(data)
      }
    end

    # ------------------------------------------------------------
    # VALIDATION (STRICT BY DESIGN)
    # ------------------------------------------------------------
    def validate_invitation_data(data)
      errors = []
      errors << "Phone number missing" if data[:phone_number].blank?
      errors << "Learner number(s) missing" if
        data[:learner_number].blank? && data[:learner_numbers].blank?
      errors
    end

    # ------------------------------------------------------------
    # BACKEND LEARNER FALLBACK
    # ------------------------------------------------------------
    def populate_learner_numbers!(data)
      return if data[:learner_numbers].present? || data[:learner_number].present?
      return unless data[:phone_number].present?
      return unless data[:grade_id].present?

      phone = data[:phone_number].to_s.strip

      learners = Learner.where(
        school_id: @school_id,
        grade_id: data[:grade_id]
      ).any_of(
        { phone: phone },
        { telHome: phone },
        { telEmergency: phone }
      )

      accession_numbers = learners.map(&:accessionNumber).compact.uniq

      return if accession_numbers.empty?

      data[:learner_numbers] = accession_numbers

      Rails.logger.info(
        "🧩 Fallback mapped learners #{accession_numbers.join(', ')} for phone #{phone}"
      )
    end

    # ------------------------------------------------------------
    # DOCUMENT BUILDER
    # ------------------------------------------------------------
    def build_invitation_document(data)
      learner_numbers = data[:learner_numbers] || Array(data[:learner_number]).compact
      klass = @role == 'parent' ? LearnerInvitation : TeacherInvitation

      # Determine whether model uses invitation_token or token
      token_key = klass.fields.key?('invitation_token') ? :invitation_token : :token
      token_val = SecureRandom.urlsafe_base64(32)

      doc = {
        school_id: @school_id,
        grade_id: data[:grade_id],
        sender_id: @sender&.id,
        invited_by_id: @sender&.id, # For LearnerInvitation/TeacherInvitation validation
        recipient_phone_number: data[:phone_number],
        phone_number: data[:phone_number],
        learner_phone: data[:phone_number], # For LearnerInvitation
        learner_numbers: learner_numbers,
        learner_number: learner_numbers.first,
        role: @role,
        parent_name: data[:parent_name],
        invited_via: @invited_via,
        country_code: data[:country_code],
        country_name: data[:country_name],
        status: (klass.fields['status']&.type == Integer) ? 0 : 'pending', # Match status type (0 for Integer)
        expires_at: 7.days.from_now, # For LearnerInvitation validation
        invited_at: Time.current,
        created_at: Time.current,
        updated_at: Time.current
      }
      doc[token_key] = token_val
      doc.compact
    end

    # ------------------------------------------------------------
    # DB INSERT
    # ------------------------------------------------------------
    def insert_batch(documents)
      klass = @role == 'parent' ? LearnerInvitation : TeacherInvitation

      result = klass.collection.insert_many(documents, ordered: false)

      inserted_count = result.inserted_count
      @successful_count += inserted_count

      inserted_ids = result.inserted_ids
      created_records = klass.where(:_id.in => inserted_ids).to_a
      @created_invitations.concat(created_records)

      Rails.logger.info "✅ Inserted #{inserted_count} invitations"

    rescue Mongo::Error::BulkWriteError => e
      successful = e.result['n_inserted'] || 0

      @successful_count += successful
      @failed_count += (documents.size - successful)

      if e.result['inserted_ids'].present?
        created_records = klass.where(:_id.in => e.result['inserted_ids']).to_a
        @created_invitations.concat(created_records)
      end

      Rails.logger.error "⚠️ Batch insert partial failure: #{successful}/#{documents.size} succeeded"
      @errors << "Batch insert errors: #{e.result['write_errors']&.first(3)}"
    end
  end
end
