# app/controllers/api/v1/learners_controller.rb
class Api::V1::LearnersController < ApplicationController
  
  def bulk_upload
    begin
      learners_data = params[:data]
      
      unless learners_data.is_a?(Array)
        return render json: { 
          error: 'Invalid data format, expected array', 
          status: 'error'
        }, status: :bad_request
      end

      successful_imports = []
      failed_imports = []
      
      learners_data.each do |learner_data|
        begin
          # Extract or find school_id from nested data or params
          school_id = learner_data[:school_id] || learner_data[:schoolId] || params[:school_id]
          
          # If no school_id provided but school name exists, find or create school
          if !school_id && (learner_data[:schoolName] || learner_data['schoolName'])
            school_id = find_or_create_school(learner_data)
          end

          learner_params = {
            first_name: learner_data[:firstName] || learner_data['firstName'],
            last_name: learner_data[:lastName] || learner_data['lastName'],
            accession_number: learner_data[:accessionNumber] || learner_data['accessionNumber'],
            school_id: school_id,
            grade_id: learner_data[:gradeId] || learner_data['gradeId'] || params[:grade_id],
            gender: map_gender(learner_data[:gender] || learner_data['gender']),
            status: map_status(learner_data[:status] || learner_data['status']) || 0, # default active
            phone: learner_data[:phone] || learner_data['phone'],
            tel_emergency: learner_data[:telEmergency] || learner_data['telEmergency'],
            tel_home: learner_data[:telHome] || learner_data['telHome'],
            whatsapp: learner_data[:whatsapp] || learner_data['whatsapp'],
            telegram: learner_data[:telegram] || learner_data['telegram']
          }

          Rails.logger.debug "🔍 Creating learner with params: #{learner_params.inspect}"
          learner = Learner.new(learner_params)
          
          if learner.save
            Rails.logger.info "✅ Successfully created: #{learner.full_name}"
            successful_imports << {
              name: "#{learner.first_name} #{learner.last_name}",
              accession_number: learner.accession_number,
              school_name: learner.school&.schoolName || learner.school&.name
            }
          else
            Rails.logger.error "❌ Validation failed for #{learner_params[:first_name]}: #{learner.errors.full_messages}"
            failed_imports << {
              name: "#{learner_params[:first_name]} #{learner_params[:last_name]}",
              errors: learner.errors.full_messages
            }
          end

        rescue => e
          Rails.logger.error "❌ Learner creation failed: #{e.message}"
          Rails.logger.error "❌ Learner data: #{learner_data.inspect}"
          Rails.logger.error "❌ Learner params: #{learner_params.inspect}" if defined?(learner_params)
          
          failed_imports << {
            name: learner_data['firstName'] || learner_data[:firstName] || 'Unknown',
            errors: [e.message]
          }
        end
      end

      render json: {
        status: 'success',
        message: 'Bulk upload completed',
        summary: {
          total_processed: successful_imports.count + failed_imports.count,
          successful: successful_imports.count,
          failed: failed_imports.count
        },
        successful_imports: successful_imports,
        failed_imports: failed_imports
      }, status: :ok

    rescue => e
      Rails.logger.error "❌ Bulk upload error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      render json: { 
        error: "An error occurred during bulk upload: #{e.message}", 
        status: 'error' 
      }, status: :internal_server_error
    end
  end

  private

  def find_or_create_school(learner_data)
    school_name = learner_data[:schoolName] || learner_data['schoolName']
    school_email = learner_data[:schoolEmail] || learner_data['schoolEmail']
    province = learner_data[:province] || learner_data['province']
    user_email = learner_data[:userEmail] || learner_data['userEmail']
    
    return nil unless school_name.present?
    
    begin
      # Try to find existing school by name or email using Mongoid syntax
      query_conditions = []
      query_conditions << { schoolName: school_name } if school_name.present?
      query_conditions << { name: school_name } if school_name.present? # fallback for different field name
      query_conditions << { schoolEmail: school_email } if school_email.present?
      query_conditions << { email: school_email } if school_email.present? # fallback for different field name

      school = School.or(*query_conditions).first if query_conditions.any?

      # Create school if it doesn't exist
      unless school
        Rails.logger.info "🏫 Creating new school: #{school_name}"
        
        school_params = {
          name: school_name,           # For compatibility with existing code
          schoolName: school_name,     # For new structure
          email: school_email,         # For compatibility
          schoolEmail: school_email,   # For new structure
          province: province,
          user_email: user_email,
          city: '',                    # Set default values
          country: '',
          theme: 'light'
        }.compact # Remove nil values

        school = School.create!(school_params)
        Rails.logger.info "✅ Successfully created school: #{school.schoolName || school.name}"
      else
        Rails.logger.info "🔍 Found existing school: #{school.schoolName || school.name}"
      end

      school.id.to_s
    rescue => e
      Rails.logger.error "❌ School creation/lookup failed: #{e.message}"
      Rails.logger.error "❌ School data: #{learner_data.inspect}"
      nil
    end
  end

  def map_gender(gender_string)
    return 0 unless gender_string.present?
    
    case gender_string.to_s.downcase.strip
    when 'male', 'm', '0'
      0
    when 'female', 'f', '1'
      1
    when 'other', '2'
      2
    else
      Rails.logger.warn "⚠️ Unknown gender value: '#{gender_string}', defaulting to male"
      0 # default to male
    end
  end

  def map_status(status_string)
    return 0 unless status_string.present?
    
    case status_string.to_s.downcase.strip
    when 'active', '0'
      0
    when 'inactive', '1'
      1
    when 'graduated', '2'
      2
    else
      Rails.logger.warn "⚠️ Unknown status value: '#{status_string}', defaulting to active"
      0 # default to active
    end
  end

  # Helper method to validate required fields before processing
  def validate_learner_data(learner_data)
    required_fields = [:firstName, :lastName]
    missing_fields = []

    required_fields.each do |field|
      string_key = field.to_s
      if learner_data[field].blank? && learner_data[string_key].blank?
        missing_fields << field
      end
    end

    missing_fields
  end
end