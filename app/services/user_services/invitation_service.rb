# app/services/user_services/invitation_service.rb
module UserServices
  class InvitationService
    def initialize(params)
      @params = params.symbolize_keys
    end

    def call
      log_start
      
      school = find_school!
      learners = find_learners!(school)
      
      invitation = Invitation.create!(
        sender_id: sender_id,
        recipient_phone_number: normalized_phone,
        school: school,
        role: @params[:role] || 'parent',
        invited_via: @params[:invited_via] || 'whatsapp',
        parent_name: @params[:parent_name],
        learner_ids: learners.map { |l| l.id.to_s },
        learner_numbers: learners.map(&:accessionNumber),
        learner_names: learners.map(&:full_name),
        token: generate_token,
        status: 'pending'
      )
      
      # REMOVED: auto_link_parent!(learners) - causing errors
      
      log_success(invitation)
      
      invitation
    rescue => e
      Rails.logger.error "❌ [InvitationService] FAILED: #{e.message}"
      Rails.logger.error "   Backtrace: #{e.backtrace.first(5).join("\n   ")}" if e.backtrace
      failure_invitation(e.message)
    end

    private

    def log_start
      Rails.logger.info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      Rails.logger.info "📨 [InvitationService] START"
      Rails.logger.info "🏫 school_id=#{@params[:school_id]}"
      Rails.logger.info "👨‍👩‍👧 learner_numbers=#{learner_numbers.inspect}"
      Rails.logger.info "📞 phone=#{normalized_phone}"
    end

    def log_success(invitation)
      Rails.logger.info "✅ [InvitationService] CREATED invitation_id=#{invitation.id}"
      Rails.logger.info "   ↳ token=#{invitation.token}"
      Rails.logger.info "   ↳ learners=#{invitation.learner_ids.join(', ')}"
      Rails.logger.info "   ↳ magic_link=https://www.schoolheadoffice.com/parent?token=#{invitation.token}&school=#{URI.encode_www_form_component(invitation.school_name)}"
    end

    def find_school!
      School.find(@params[:school_id])
    rescue Mongoid::Errors::DocumentNotFound
      raise "School not found: #{@params[:school_id]}"
    end

    def find_learners!(school)
      Rails.logger.info "🔎 [InvitationService] Searching learners (robust mode)"

      learners = learner_numbers.map do |number|
        learner = find_learner_by_any_field(school, number)

        if learner
          Rails.logger.info "   ↳ ✅ matched learner #{learner.id} accession=#{learner.accessionNumber}"
        else
          Rails.logger.warn "   ↳ ⚠️  No learner match for #{number}"
        end

        learner
      end.compact.uniq

      raise "Learner not found: #{learner_numbers.join(', ')}" if learners.empty?

      learners
    end

    def find_learner_by_any_field(school, number)
      regex = /^#{Regexp.escape(number)}$/i
      school_ids = [school.id, school.id.to_s]

      learner = Learner.where(:school_id.in => school_ids)
                       .any_of(
                         { accessionNumber: regex },
                         { learner_number: regex },
                         { learnerNumber: regex },
                         { admission_number: regex }
                       ).first
      
      return learner if learner

      Rails.logger.warn "   ↳ 🔄 Trying raw Mongo fallback for #{number}"
      
      result = Learner.collection.find(
        "school_id" => { "$in" => school_ids.map { |id| id.is_a?(String) ? id : id.to_s } },
        "$or" => [
          { "accessionNumber" => regex },
          { "learner_number" => regex },
          { "learnerNumber" => regex },
          { "admission_number" => regex }
        ]
      ).limit(1).first

      result ? Learner.new(result) : nil
    end

    # REMOVED: auto_link_parent! method entirely

    def learner_numbers
      nums =
        if @params[:learner_numbers].present?
          @params[:learner_numbers]
        elsif @params[:learner_number].present?
          [@params[:learner_number]]
        else
          []
        end

      nums.map(&:to_s).map(&:strip).reject(&:blank?).uniq
    end

    def normalized_phone
      phone = @params[:phone_number].to_s.strip
      return phone if phone.start_with?('27')
      phone.start_with?('0') ? phone.sub(/^0/, '27') : phone
    end

    def sender_id
      @params[:sender_id]
    end

    def sender_auth0_id
      @params[:sender_id]
    end

    def generate_token
      loop do
        token = SecureRandom.urlsafe_base64(32)
        break token unless Invitation.where(token: token).exists?
      end
    end

    def failure_invitation(message)
      invitation = Invitation.new
      invitation.errors.add(:base, message)
      invitation
    end
  end
end