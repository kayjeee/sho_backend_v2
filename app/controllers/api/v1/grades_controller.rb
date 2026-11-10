module Api
  module V1
    class GradesController < Api::V1::BaseController
      before_action :set_school
      before_action :set_grade, only: [:show, :update, :destroy, :learners, :teachers, :stats]
      before_action :authorize_admin!, except: [:index, :show]

      # GET /api/v1/schools/:school_id/grades
      # GET /api/v1/grades
      def index
        # 1. Grab the school parameter safely from any route style variation
        school_param = params[:school_id] || params[:schoolId]

        if school_param.blank?
          return render json: {
            success: false,
            error: "School context identifier is required."
          }, status: :bad_request
        end

        # 2. Resolve the identifier whether it's a BSON ObjectId, text slug, email, or owner auth0 id.
        school = find_school_by_id_or_slug(school_param)
        school_id = school&.id

        if school_id.nil?
          return render json: {
            success: false,
            error: "Target school location could not be found."
          }, status: :not_found
        end

        # 3. Retrieve the matching grade records
        @grades = Grade.where(school_id: school_id)

        render json: {
          success: true,
          total: @grades.count,
          grades: @grades.map { |grade|
            {
              id: grade.id.to_s,
              name: grade.name,
              school_id: school_id.to_s
            }
          }
        }, status: :ok
      end

      # GET /api/v1/schools/:school_id/grades/:id
      # GET /api/v1/grades/:id
      def show
        render json: {
          success: true,
          grade: grade_json(@grade, detailed: true)
        }
      end

      # POST /api/v1/schools/:school_id/grades
      def create
        @grade = @school.grades.build(grade_params)

        if @grade.save
          render json: {
            success: true,
            message: "Grade created successfully",
            grade: grade_json(@grade)
          }, status: :created
        else
          render json: {
            success: false,
            errors: @grade.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # PATCH/PUT /api/v1/grades/:id
      def update
        if @grade.update(grade_params)
          render json: {
            success: true,
            message: "Grade updated successfully",
            grade: grade_json(@grade)
          }
        else
          render json: {
            success: false,
            errors: @grade.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/grades/:id
      def destroy
        # Check if grade has any classes
        if @grade.school_classes.exists?
          render json: {
            success: false,
            error: "Cannot delete grade with existing classes. Transfer or delete classes first."
          }, status: :unprocessable_entity
        else
          @grade.destroy
          render json: {
            success: true,
            message: "Grade deleted successfully"
          }
        end
      end

      # GET /api/v1/grades/:id/learners
      def learners
        learners = @grade.all_learners
        render json: {
          success: true,
          total: learners.count,
          learners: learners.map { |l| learner_json(l) }
        }
      end

      # GET /api/v1/grades/:id/teachers
      def teachers
        teachers = @grade.all_teachers
        render json: {
          success: true,
          total: teachers.count,
          teachers: teachers
        }
      end

      # GET /api/v1/grades/:id/stats
      def stats
        render json: {
          success: true,
          stats: {
            total_classes: @grade.school_classes.count,
            total_learners: @grade.total_learners,
            total_teachers: @grade.all_teachers.count,
            capacity_utilization: @grade.capacity_utilization,
            subjects_offered: @grade.subjects_offered
          }
        }
      end

      # GET /api/v1/grades/:id/hierarchy
      def hierarchy
        render json: {
          success: true,
          grade: serialize_grade_with_hierarchy(@grade)
        }
      end

      private

      def serialize_grade_with_hierarchy(grade)
        {
          id: grade.id.to_s,
          name: grade.name,
          classes: grade.school_classes.map { |cls|
            assigned_learners = Learner.where(school_class_id: cls.id)
            {
              id: cls.id.to_s,
              name: cls.name,
              learners: assigned_learners.map { |l|
                {
                  id: l.id.to_s,
                  name: "#{l.first_name} #{l.last_name}".presence || "Unnamed Learner",
                  admission_number: l.try(:accession_number) || "LNR-#{l.id.to_s.last(4).upcase}",
                  # Nest parent data array cleanly right here:
                  parents: l.parents.map { |p|
                    {
                      id: p.id.to_s,
                      name: p.try(:name) || p.email.split('@').first.capitalize,
                      email: p.email,
                      phone: p.try(:phone_number) || p.try(:phone) || "No Contact"
                    }
                  }
                }
              }
            }
          }
        }
      end

      def set_school
        school_param = params[:school_id] || params[:schoolId]
        @school = find_school_by_id_or_slug(school_param)

        if @school.nil? && params[:id].present? && action_name != 'create'
          begin
            @grade = Grade.find(params[:id])
            @school = @grade.school if @grade
          rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
            # Handled by set_grade
          end
        end

        unless @school
          render json: { success: false, error: "School not found" }, status: :not_found
        end
      rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
        render json: { success: false, error: "School not found" }, status: :not_found
      end

      def set_grade
        @grade ||= @school ? @school.grades.find(params[:id]) : Grade.find(params[:id])
      rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
        render json: { success: false, error: "Grade not found" }, status: :not_found
      end

      def grade_params
        params.require(:grade).permit(:name, :level, :description, :order)
      end

      def grade_json(grade, detailed: false)
        json = {
          id: grade.id.to_s,
          school_id: grade.school_id.to_s,
          name: grade.name,
          level: grade.level || 0,
          description: grade.description,
          order: grade.order,
          total_classes: grade.school_classes.count,
          total_learners: grade.total_learners,
          created_at: grade.created_at,
          updated_at: grade.updated_at
        }

        if detailed
          json[:classes] = grade.school_classes.map { |c| class_json(c) }
          json[:teachers] = grade.all_teachers
          json[:subjects] = grade.subjects_offered
          json[:capacity_utilization] = grade.capacity_utilization
        end

        json
      end

      def class_json(school_class)
        {
          id: school_class.id.to_s,
          name: school_class.name,
          capacity: school_class.capacity,
          current_learners: school_class.learner_ids.count,
          class_teacher_id: school_class.class_teacher_id,
          subject_teachers: school_class.subject_teacher_ids
        }
      end

      def learner_json(learner)
        {
          id: learner.id.to_s,
          first_name: learner.first_name,
          last_name: learner.last_name,
          email: learner.email,
          grade: learner.grade&.name,
          class: learner.try(:school_class)&.try(:name)
        }
      end

      def authorize_admin!
        # head :unauthorized unless current_user&.has_role?(:admin, @school)
      end
    end
  end
end
