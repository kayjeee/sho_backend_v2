module Api
  module V1
    class ClassesController < ApplicationController
      before_action :set_school
      before_action :set_grade
      before_action :set_class, only: [:show, :update, :destroy, :assign_teacher, :move_learner, :learners, :stats]
      before_action :authorize_admin!

      # GET /api/v1/schools/:school_id/grades/:grade_id/classes
      def index
        classes = @grade.school_classes
        render json: {
          success: true,
          classes: classes.map { |c| class_json(c, detailed: false) }
        }
      end

      # GET /api/v1/schools/:school_id/grades/:grade_id/classes/:id
      def show
        render json: {
          success: true,
          class: class_json(@school_class, detailed: true)
        }
      end

      # POST /api/v1/schools/:school_id/grades/:grade_id/classes
      def create
        @school_class = @grade.school_classes.build(class_params)

        if @school_class.save
          render json: {
            success: true,
            message: "Class created successfully",
            class: class_json(@school_class)
          }, status: :created
        else
          render json: {
            success: false,
            errors: @school_class.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # PATCH/PUT /api/v1/schools/:school_id/grades/:grade_id/classes/:id
      def update
        if @school_class.update(class_params)
          render json: {
            success: true,
            message: "Class updated successfully",
            class: class_json(@school_class)
          }
        else
          render json: {
            success: false,
            errors: @school_class.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/schools/:school_id/grades/:grade_id/classes/:id
      def destroy
        if @school_class.learner_ids.any?
          render json: {
            success: false,
            error: "Cannot delete class with enrolled learners. Transfer learners first."
          }, status: :unprocessable_entity
        else
          @school_class.destroy
          render json: {
            success: true,
            message: "Class deleted successfully"
          }
        end
      end

      # POST /api/v1/schools/:school_id/grades/:grade_id/classes/:id/assign_teacher
      def assign_teacher
        teacher_id = params[:teacher_id]
        role = params[:role] # 'class_teacher' or 'subject_teacher'
        subject_id = params[:subject_id] # Required for subject_teacher

        case role
        when 'class_teacher'
          if @school_class.assign_class_teacher(teacher_id)
            message = "Class teacher assigned successfully"
          else
            return render json: { success: false, errors: @school_class.errors.full_messages }, status: :unprocessable_entity
          end
        when 'subject_teacher'
          if subject_id.blank?
            return render json: { success: false, error: "subject_id required for subject teacher" },
                          status: :unprocessable_entity
          end
          if @school_class.assign_subject_teacher(subject_id, teacher_id)
            message = "Subject teacher assigned successfully"
          else
            return render json: { success: false, errors: @school_class.errors.full_messages }, status: :unprocessable_entity
          end
        else
          return render json: { success: false, error: "Invalid role. Use 'class_teacher' or 'subject_teacher'" },
                        status: :unprocessable_entity
        end

        render json: {
          success: true,
          message: message,
          class: class_json(@school_class)
        }
      end

      # POST /api/v1/schools/:school_id/grades/:grade_id/classes/:id/move_learner
      def move_learner
        learner_id = params[:learner_id]
        target_class_id = params[:target_class_id]

        # Find target class
        begin
          target_class = @grade.school_classes.find(target_class_id)
        rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
          return render json: { success: false, error: "Target class not found" }, status: :not_found
        end

        # Validate learner exists in source class
        unless @school_class.learner_ids.include?(BSON::ObjectId.from_string(learner_id.to_s))
          return render json: { success: false, error: "Learner not found in source class" },
                        status: :unprocessable_entity
        end

        # Check capacity in target class
        if target_class.full?
          return render json: { success: false, error: "Target class is at full capacity" },
                        status: :unprocessable_entity
        end

        # Atomic move operation
        @school_class.pull(learner_ids: BSON::ObjectId.from_string(learner_id.to_s))
        target_class.add_to_set(learner_ids: BSON::ObjectId.from_string(learner_id.to_s))

        # Update learner's grade and class references
        Learner.find(learner_id).update(
          grade_id: @grade.id,
          school_class_id: target_class.id
        )

        render json: {
          success: true,
          message: "Learner moved successfully",
          source_class: class_json(@school_class.reload),
          target_class: class_json(target_class.reload)
        }
      end

      # GET /api/v1/schools/:school_id/grades/:grade_id/classes/:id/learners
      def learners
        learners = Learner.where(id: { "$in" => @school_class.learner_ids })
        render json: {
          success: true,
          total: learners.count,
          capacity: @school_class.capacity,
          utilization: "#{learners.count}/#{@school_class.capacity}",
          learners: learners.map { |l| learner_json(l) }
        }
      end

      # GET /api/v1/schools/:school_id/grades/:grade_id/classes/:id/stats
      def stats
        render json: {
          success: true,
          stats: {
            name: @school_class.name,
            total_learners: @school_class.learner_ids.count,
            capacity: @school_class.capacity,
            utilization_percentage: (@school_class.learner_ids.count.to_f / @school_class.capacity * 100).round(1),
            has_class_teacher: @school_class.class_teacher_id.present?,
            subject_teachers_count: @school_class.subject_teacher_ids.keys.count,
            grade_name: @grade.name
          }
        }
      end

      private

      def set_school
        school_id = params[:school_id]
        if BSON::ObjectId.legal?(school_id)
          @school = School.find(school_id)
        else
          lookup_name = school_id.to_s.gsub('-', ' ')
          @school = School.where(schoolName: /^#{Regexp.escape(lookup_name)}$/i).first ||
                    School.where(schoolEmail: /^#{Regexp.escape(school_id.to_s)}$/i).first
        end

        unless @school
          render json: { success: false, error: "School not found" }, status: :not_found
        end
      rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
        render json: { success: false, error: "School not found" }, status: :not_found
      end

      def set_grade
        @grade = @school.grades.find(params[:grade_id])
      rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
        render json: { success: false, error: "Grade not found" }, status: :not_found
      end

      def set_class
        @school_class = @grade.school_classes.find(params[:id])
      rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
        render json: { success: false, error: "Class not found" }, status: :not_found
      end

      def class_params
        params.require(:class).permit(:name, :capacity, :class_teacher_id)
      end

      def class_json(school_class, detailed: false)
        utilization_percentage = if school_class.capacity.to_i > 0
                                   (school_class.learner_ids.count.to_f / school_class.capacity * 100).round(1)
                                 else
                                   0
                                 end
        json = {
          id: school_class.id.to_s,
          name: school_class.name,
          capacity: school_class.capacity,
          current_learners: school_class.learner_ids.count,
          utilization: "#{school_class.learner_ids.count}/#{school_class.capacity}",
          utilization_percentage: utilization_percentage
        }

        if detailed
          json[:class_teacher_id] = school_class.class_teacher_id
          json[:subject_teachers] = school_class.subject_teacher_ids
          json[:learner_ids] = school_class.learner_ids.map(&:to_s)
          json[:grade_name] = @grade.name
          json[:school_name] = @school.schoolName
        end

        json
      end

      def learner_json(learner)
        {
          id: learner.id.to_s,
          first_name: learner.first_name,
          last_name: learner.last_name,
          email: learner.email,
          full_name: "#{learner.first_name} #{learner.last_name}"
        }
      end

      def authorize_admin!
        # Implement your admin authorization
      end
    end
  end
end
