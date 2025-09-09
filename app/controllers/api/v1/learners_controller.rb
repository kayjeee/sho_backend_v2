class Api::V1::LearnersController < ApplicationController
  before_action :set_learner, only: [:show, :update, :destroy, :graduate, :transfer, :activate, :deactivate]
  before_action :set_grade, only: [:index], if: -> { params[:grade_id].present? }
  before_action :set_user, only: [:bulk_upload]

  # GET /api/v1/learners or /api/v1/grades/:grade_id/learners
  def index
    learners = if @grade
                 @grade.learners.includes(:school, :grade)
               else
                 filtered_learners = Learner.includes(:school, :grade)
                 filtered_learners = filtered_learners.where(school_id: params[:school_id]) if params[:school_id].present?
                 filtered_learners = filtered_learners.where(grade_id: params[:grade_id]) if params[:grade_id].present?
                 filtered_learners = filtered_learners.where(status: params[:status]) if params[:status].present?
                 filtered_learners
               end

    page = [params[:page].to_i, 1].max
    per_page = [[params[:per_page].to_i, 20].max, 100].min

    total_count = learners.count
    paginated_learners = learners.skip((page - 1) * per_page).limit(per_page)

    render json: {
      status: 'success',
      data: paginated_learners.map { |l| learner_response(l) },
      pagination: {
        current_page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: (total_count.to_f / per_page).ceil
      }
    }, status: :ok
  rescue => e
    Rails.logger.error("❌ Error fetching learners: #{e.message}")
    render json: { error: 'Failed to fetch learners', status: 'error' }, status: :internal_server_error
  end

  # GET /api/v1/learners/search?q=...
  def search
    query = params[:q]
    if query.blank?
      return render json: { error: 'Search query is required', status: 'error' }, status: :bad_request
    end

    search_results = Learner.where(
      "$or" => [
        { first_name: /#{Regexp.escape(query)}/i },
        { last_name: /#{Regexp.escape(query)}/i },
        { accession_number: /#{Regexp.escape(query)}/i }
      ]
    ).includes(:school, :grade).limit(50)

    render json: {
      status: 'success',
      data: search_results.map { |l| learner_response(l) },
      count: search_results.size
    }, status: :ok
  rescue => e
    Rails.logger.error("❌ Error searching learners: #{e.message}")
    render json: { error: 'Search failed', status: 'error' }, status: :internal_server_error
  end

  # GET /api/v1/learners/:id
  def show
    render json: { status: 'success', data: learner_response(@learner) }, status: :ok
  end

  # POST /api/v1/learners
  def create
    learner_params_hash = learner_params.to_h

    if learner_params_hash[:school_id].blank? && params[:school_name].present?
      school_data = {
        schoolName: params[:school_name],
        schoolEmail: params[:school_email],
        province: params[:province],
        userEmail: params[:user_email]
      }
      learner_params_hash[:school_id] = find_or_create_school(school_data)
    end

    learner = Learner.new(learner_params_hash)

    if learner.save
      Rails.logger.info("✅ Successfully created learner: #{learner.full_name}")
      render json: { status: 'success', message: 'Learner created successfully', data: learner_response(learner) }, status: :created
    else
      render json: { error: 'Validation failed', status: 'error', errors: learner.errors.full_messages }, status: :unprocessable_entity
    end
  rescue => e
    Rails.logger.error("❌ Error creating learner: #{e.message}")
    render json: { error: "Failed to create learner: #{e.message}", status: 'error' }, status: :internal_server_error
  end

  # PATCH/PUT /api/v1/learners/:id
  def update
    if @learner.update(learner_params)
      Rails.logger.info("✅ Successfully updated learner: #{@learner.full_name}")
      render json: { status: 'success', message: 'Learner updated successfully', data: learner_response(@learner) }, status: :ok
    else
      render json: { error: 'Validation failed', status: 'error', errors: @learner.errors.full_messages }, status: :unprocessable_entity
    end
  rescue => e
    Rails.logger.error("❌ Error updating learner: #{e.message}")
    render json: { error: "Failed to update learner: #{e.message}", status: 'error' }, status: :internal_server_error
  end

  # DELETE /api/v1/learners/:id
  def destroy
    if @learner.destroy
      Rails.logger.info("✅ Successfully deleted learner: #{@learner.full_name}")
      render json: { status: 'success', message: 'Learner deleted successfully' }, status: :ok
    else
      render json: { error: 'Failed to delete learner', status: 'error', errors: @learner.errors.full_messages }, status: :unprocessable_entity
    end
  rescue => e
    Rails.logger.error("❌ Error deleting learner: #{e.message}")
    render json: { error: "Failed to delete learner: #{e.message}", status: 'error' }, status: :internal_server_error
  end

  # PATCH /api/v1/learners/:id/graduate
  def graduate
    if @learner.update(status: 2)
      Rails.logger.info("🎓 Successfully graduated learner: #{@learner.full_name}")
      render json: { status: 'success', message: 'Learner graduated successfully', data: learner_response(@learner) }, status: :ok
    else
      render json: { error: 'Failed to graduate learner', status: 'error', errors: @learner.errors.full_messages }, status: :unprocessable_entity
    end
  rescue => e
    Rails.logger.error("❌ Error graduating learner: #{e.message}")
    render json: { error: "Failed to graduate learner: #{e.message}", status: 'error' }, status: :internal_server_error
  end

  # PATCH /api/v1/learners/:id/transfer
  def transfer
    new_school_id = params[:new_school_id]
    new_grade_id = params[:new_grade_id]

    if new_school_id.blank?
      return render json: { error: 'New school ID is required for transfer', status: 'error' }, status: :bad_request
    end

    update_params = { school_id: new_school_id }
    update_params[:grade_id] = new_grade_id if new_grade_id.present?

    if @learner.update(update_params)
      Rails.logger.info("🔄 Successfully transferred learner: #{@learner.full_name}")
      render json: { status: 'success', message: 'Learner transferred successfully', data: learner_response(@learner) }, status: :ok
    else
      render json: { error: 'Failed to transfer learner', status: 'error', errors: @learner.errors.full_messages }, status: :unprocessable_entity
    end
  rescue => e
    Rails.logger.error("❌ Error transferring learner: #{e.message}")
    render json: { error: "Failed to transfer learner: #{e.message}", status: 'error' }, status: :internal_server_error
  end

  # PATCH /api/v1/learners/:id/activate
  def activate
    if @learner.update(status: 0)
      Rails.logger.info("✅ Successfully activated learner: #{@learner.full_name}")
      render json: { status: 'success', message: 'Learner activated successfully', data: learner_response(@learner) }, status: :ok
    else
      render json: { error: 'Failed to activate learner', status: 'error', errors: @learner.errors.full_messages }, status: :unprocessable_entity
    end
  rescue => e
    Rails.logger.error("❌ Error activating learner: #{e.message}")
    render json: { error: "Failed to activate learner: #{e.message}", status: 'error' }, status: :internal_server_error
  end

  # PATCH /api/v1/learners/:id/deactivate
  def deactivate
    if @learner.update(status: 1)
      Rails.logger.info("⏸️ Successfully deactivated learner: #{@learner.full_name}")
      render json: { status: 'success', message: 'Learner deactivated successfully', data: learner_response(@learner) }, status: :ok
    else
      render json: { error: 'Failed to deactivate learner', status: 'error', errors: @learner.errors.full_messages }, status: :unprocessable_entity
    end
  rescue => e
    Rails.logger.error("❌ Error deactivating learner: #{e.message}")
    render json: { error: "Failed to deactivate learner: #{e.message}", status: 'error' }, status: :internal_server_error
  end

  # POST /api/v1/learners/bulk_upload
  def bulk_upload
    learners_data = params[:data]

    unless learners_data.is_a?(Array)
      return render json: { error: 'Invalid data format, expected array', status: 'error' }, status: :bad_request
    end

    successful_imports = []
    failed_imports = []

    Learner.transaction do
      learners_data.each do |learner_data|
        missing_fields = validate_learner_data(learner_data)
        if missing_fields.any?
          failed_imports << {
            name: learner_data[:firstName] || learner_data['firstName'] || 'Unknown',
            errors: ["Missing required fields: #{missing_fields.join(', ')}"]
          }
          next
        end

        school_id = learner_data[:school_id] || learner_data[:schoolId] || params[:school_id]
        if !school_id && (learner_data[:schoolName] || learner_data['schoolName'])
          school_id = find_or_create_school(learner_data)
        end

        learner_params_hash = {
          first_name: learner_data[:firstName] || learner_data['firstName'],
          last_name: learner_data[:lastName] || learner_data['lastName'],
          accession_number: learner_data[:accessionNumber] || learner_data['accessionNumber'],
          school_id: school_id,
          grade_id: learner_data[:gradeId] || learner_data['gradeId'] || params[:grade_id],
          gender: map_gender(learner_data[:gender] || learner_data['gender']),
          status: map_status(learner_data[:status] || learner_data['status']) || 0,
          phone: learner_data[:phone] || learner_data['phone'],
          tel_emergency: learner_data[:telEmergency] || learner_data['telEmergency'],
          tel_home: learner_data[:telHome] || learner_data['telHome'],
          whatsapp: learner_data[:whatsapp] || learner_data['whatsapp'],
          telegram: learner_data[:telegram] || learner_data['telegram']
        }

        learner = Learner.new(learner_params_hash)
        if learner.save
          Rails.logger.info("✅ Successfully created: #{learner.full_name}")
          successful_imports << {
            id: learner.id.to_s,
            name: "#{learner.first_name} #{learner.last_name}",
            accession_number: learner.accession_number,
            school_name: learner.school&.schoolName || learner.school&.name
          }
        else
          Rails.logger.error("❌ Validation failed for #{learner_params_hash[:first_name]}: #{learner.errors.full_messages}")
          failed_imports << {
            name: "#{learner_params_hash[:first_name]} #{learner_params_hash[:last_name]}",
            errors: learner.errors.full_messages
          }
        end
      rescue => e
        Rails.logger.error("❌ Learner creation failed: #{e.message}")
        Rails.logger.error("❌ Learner data: #{learner_data.inspect}")

        failed_imports << {
          name: learner_data['firstName'] || learner_data[:firstName] || 'Unknown',
          errors: [e.message]
        }
      end
    end

    # Mark onboarding step complete if imports were successful
    if successful_imports.any?
      if @user.onboarding_status.present?
        @user.onboarding_status.complete_step!("upload_learners")
        @user.save!
      else
        Rails.logger.error("OnboardingStatus not found for user #{@user.id}")
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
    Rails.logger.error("❌ Bulk upload error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    render json: { error: "An error occurred during bulk upload: #{e.message}", status: 'error' }, status: :internal_server_error
  end

  private

  def set_user
    # Replace with actual auth logic as needed
    @user = User.first
  end

  def set_learner
    @learner = Learner.find(params[:id])
  rescue Mongoid::Errors::DocumentNotFound
    render json: { error: 'Learner not found', status: 'error' }, status: :not_found
  end

  def set_grade
    @grade = Grade.find(params[:grade_id]) if params[:grade_id].present?
  rescue Mongoid::Errors::DocumentNotFound
    render json: { error: 'Grade not found', status: 'error' }, status: :not_found
  end

  def learner_params
    params.require(:learner).permit(
      :first_name, :last_name, :accession_number, :school_id, :grade_id,
      :gender, :status, :phone, :tel_emergency, :tel_home, :whatsapp, :telegram
    )
  end

  def learner_response(learner)
    {
      id: learner.id.to_s,
      first_name: learner.first_name,
      last_name: learner.last_name,
      full_name: learner.full_name,
      accession_number: learner.accession_number,
      gender: learner.gender,
      gender_display: gender_display(learner.gender),
      status: learner.status,
      status_display: status_display(learner.status),
      phone: learner.phone,
      tel_emergency: learner.tel_emergency,
      tel_home: learner.tel_home,
      whatsapp: learner.whatsapp,
      telegram: learner.telegram,
      school: learner.school ? {
        id: learner.school.id.to_s,
        name: learner.school.schoolName || learner.school.name,
        email: learner.school.schoolEmail || learner.school.email
      } : nil,
      grade: learner.grade ? {
        id: learner.grade.id.to_s,
        name: learner.grade.name || learner.grade.gradeName
      } : nil,
      created_at: learner.created_at,
      updated_at: learner.updated_at
    }
  end

  def gender_display(gender)
    case gender
    when 0 then 'Male'
    when 1 then 'Female'
    when 2 then 'Other'
    else 'Unknown'
    end
  end

  def status_display(status)
    case status
    when 0 then 'Active'
    when 1 then 'Inactive'
    when 2 then 'Graduated'
    else 'Unknown'
    end
  end

  def find_or_create_school(learner_data)
    school_name = learner_data[:schoolName] || learner_data['schoolName']
    return nil unless school_name.present?

    school_email = learner_data[:schoolEmail] || learner_data['schoolEmail']
    province = learner_data[:province] || learner_data['province']
    user_email = learner_data[:userEmail] || learner_data['userEmail']

    query_conditions = []
    query_conditions << { schoolName: school_name }
    query_conditions << { name: school_name }
    query_conditions << { schoolEmail: school_email }
    query_conditions << { email: school_email }

    school = School.or(*query_conditions).first if query_conditions.any?

    unless school
      school_params = {
        name: school_name,
        schoolName: school_name,
        email: school_email,
        schoolEmail: school_email,
        province: province,
        user_email: user_email,
        city: '',
        country: '',
        theme: 'light'
      }.compact

      school = School.create!(school_params)
      Rails.logger.info "🏫 Created new school: #{school.schoolName || school.name}"
    end

    school.id.to_s
  rescue => e
    Rails.logger.error "❌ School creation/lookup failed: #{e.message}"
    nil
  end

  def map_gender(val)
    return 0 unless val.present?

    case val.to_s.downcase.strip
    when 'male', 'm', '0' then 0
    when 'female', 'f', '1' then 1
    when 'other', '2' then 2
    else 0
    end
  end

  def map_status(val)
    return 0 unless val.present?

    case val.to_s.downcase.strip
    when 'active', '0' then 0
    when 'inactive', '1' then 1
    when 'graduated', '2' then 2
    else 0
    end
  end

  def validate_learner_data(learner_data)
    required = [:firstName, :lastName]
    required.select do |field|
      learner_data[field].blank? && learner_data[field.to_s].blank?
    end
  end
end
