module PrCodeServices
  class CreateService
    def self.call(params, school)
      # In a real system, the code generation would be more robust
      # to ensure uniqueness and follow the specified format.
      code = generate_code(school, params[:recipient_type])
      
      pr_code = PrCode.new(
        code: code,
        recipient_type: params[:recipient_type],
        invite_id: params[:invite_id],
        expires_at: 1.year.from_now, # Example expiration
        school: school
      )

      if pr_code.save
        OpenStruct.new(success?: true, pr_code: pr_code)
      else
        OpenStruct.new(success?: false, errors: pr_code.errors.full_messages)
      end
    end

    private

    def self.generate_code(school, type)
      random_part = SecureRandom.hex(3).upcase
      "#{school.schoolName.upcase.split.first}-#{type.upcase}-#{random_part}"
    end
  end
end
