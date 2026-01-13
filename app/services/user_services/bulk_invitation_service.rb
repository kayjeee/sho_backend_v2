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
    end
    
    def call
      return ServiceResult.new(
        success: false, 
        errors: ["No invitations provided"]
      ) if @invitations_data.empty?
      
      Rails.logger.info "📦 Starting bulk invitation creation for #{@invitations_data.size} invitations"
      start_time = Time.current
      
      # Process in batches for optimal performance
      @invitations_data.each_slice(BATCH_SIZE).with_index do |batch, batch_index|
        process_batch(batch, batch_index)
      end
      
      elapsed_time = Time.current - start_time
      
      Rails.logger.info "✅ Bulk invitation completed in #{elapsed_time.round(2)}s"
      Rails.logger.info "   Successful: #{@successful_count}, Failed: #{@failed_count}"
      
      ServiceResult.new(
        success: @failed_count == 0,
        errors: @errors,
        invitations: nil, # Don't return all invitations to save memory
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
        stats: {
          total: @invitations_data.size,
          successful: @successful_count,
          failed: @failed_count
        }
      )
    end
    
    private
    
    def process_batch(batch, batch_index)
      Rails.logger.info "🔄 Processing batch #{batch_index + 1} (#{batch.size} invitations)"
      
      # Prepare all invitation documents
      valid_invitations = []
      
      batch.each_with_index do |invitation_data, index|
        result = prepare_invitation(invitation_data, batch_index, index)
        
        if result[:valid]
          valid_invitations << result[:document]
        else
          @failed_count += 1
          @failed_invitations << {
            data: invitation_data,
            errors: result[:errors]
          }
        end
      end
      
      # Bulk insert valid invitations
      if valid_invitations.any?
        insert_batch(valid_invitations)
      end
    end
    
    def prepare_invitation(data, batch_index, index)
      errors = validate_invitation_data(data)
      
      if errors.any?
        Rails.logger.warn "⚠️  Invalid invitation at batch #{batch_index}, index #{index}: #{errors}"
        return { valid: false, errors: errors }
      end
      
      {
        valid: true,
        document: build_invitation_document(data)
      }
    end
    
    def validate_invitation_data(data)
      errors = []
      errors << "Phone number missing" if data[:phone_number].blank?
      errors << "Learner number(s) missing" if data[:learner_number].blank? && data[:learner_numbers].blank?
      errors
    end
    
    def build_invitation_document(data)
      learner_numbers = data[:learner_numbers] || Array(data[:learner_number]).compact
      
      {
        sender_id: @sender&.id,
        recipient_phone_number: data[:phone_number],
        phone_number: data[:phone_number],
        school_id: @school_id,
        learner_numbers: learner_numbers,
        learner_number: learner_numbers.first,
        role: @role,
        parent_name: data[:parent_name],
        grade_id: data[:grade_id],
        invited_via: @invited_via,
        country_code: data[:country_code],
        country_name: data[:country_name],
        status: 'pending',
        token: SecureRandom.urlsafe_base64(32),
        created_at: Time.current,
        updated_at: Time.current
      }.compact
    end
    
    def insert_batch(invitations)
      klass = @role == 'parent' ? LearnerInvitation : TeacherInvitation
      
      begin
        # Use MongoDB's native bulk insert for maximum performance
        result = klass.collection.insert_many(invitations, ordered: false)
        
        inserted_count = result.inserted_count
        @successful_count += inserted_count
        
        Rails.logger.info "✅ Inserted #{inserted_count} invitations"
      rescue Mongo::Error::BulkWriteError => e
        # Even with errors, some documents may have been inserted
        successful = e.result['n_inserted'] || 0
        @successful_count += successful
        @failed_count += (invitations.size - successful)
        
        Rails.logger.error "⚠️  Batch insert partial failure: #{successful}/#{invitations.size} succeeded"
        @errors << "Batch insert errors: #{e.result['write_errors']&.first(3)}"
      end
    end
  end
end