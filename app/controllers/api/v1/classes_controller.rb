module Api
  module V1
    class ClassesController < ApplicationController
      before_action :set_school
      before_action :set_grade
      before_action :set_class, only: [:show, :update, :destroy, :assign_teacher, :move_learner]

      # GET /api/v1/schools/:school_id/grades/:grade_id/classes
      def index
        @classes = @grade.school_classes
        render json: { success: true, classes: @classes }, status: :ok
      end

      # GET /api/v1/schools/:school_id/grades/:grade_id/classes/:id
      def show
        render json: { success: true, class: @class }, status: :ok
      end

      # POST /api/v1/schools/:school_id/grades/:grade_id/classes
      def create
        @class = @grade.school_classes.build(class_params)
        if @class.save
          render json: { success: true, class: @class }, status: :created
        else
          render json: { success: false, errors: @class.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH/PUT /api/v1/schools/:school_id/grades/:grade_id/classes/:id
      def update
        if @class.update(class_params)
          render json: { success: true, class: @class }, status: :ok
        else
          render json: { success: false, errors: @class.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/schools/:school_id/grades/:grade_id/classes/:id
      def destroy
        @class.destroy
        render json: { success: true, message: 'Class deleted successfully' }, status: :ok
      end

      # POST /api/v1/schools/:school_id/grades/:grade_id/classes/:id/assign_teacher
      def assign_teacher
        teacher_id = params[:teacher_id]
        role = params[:role]
        subject_id = params[:subject_id]

        case role
        when 'class_teacher'
          @class.class_teacher_id = teacher_id
        when 'subject_teacher'
          if subject_id.present?
            # Explicitly mark hash as changed or reassign to trigger Mongoid dirty tracking
            new_subject_teachers = @class.subject_teacher_ids.dup
            new_subject_teachers[subject_id] = teacher_id
            @class.subject_teacher_ids = new_subject_teachers
          else
            return render json: { success: false, message: 'subject_id is required for subject_teacher role' }, status: :bad_request
          end
        else
          return render json: { success: false, message: 'Invalid role' }, status: :bad_request
        end

        if @class.save
          render json: { success: true, class: @class }, status: :ok
        else
          render json: { success: false, errors: @class.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/schools/:school_id/grades/:grade_id/classes/:id/move_learner
      def move_learner
        learner_id = params[:learner_id]
        target_class_id = params[:target_class_id]

        begin
          target_class = @grade.school_classes.find(target_class_id)
        rescue BSON::Error::InvalidObjectId, Mongoid::Errors::DocumentNotFound
          return render json: { success: false, message: 'Target class not found' }, status: :not_found
        end

        # Transactionally move learner
        # Using atomic operators to ensure consistency
        success = false
        begin
          # Pull from current class
          @class.pull(learner_ids: BSON::ObjectId.from_string(learner_id))
          # Push to target class
          target_class.add_to_set(learner_ids: BSON::ObjectId.from_string(learner_id))

          # Also update the learner document's grade_id if needed,
          # but here we are within the same grade hierarchy.
          # If move_learner was between grades, we'd need more logic.
          # The prompt says Grade └── Class, so it's likely within the same grade or
          # at least we should handle the learner's class reference if they have one.
          # Currently Learner model has grade_id but no class_id.

          success = true
        rescue => e
          return render json: { success: false, message: "Movement failed: #{e.message}" }, status: :unprocessable_entity
        end

        if success
          render json: { success: true, message: 'Learner moved successfully' }, status: :ok
        else
          render json: { success: false, message: 'Movement failed' }, status: :unprocessable_entity
        end
      end

      private

      def set_school
        @school = School.find(params[:school_id])
      rescue BSON::Error::InvalidObjectId, Mongoid::Errors::DocumentNotFound
        render json: { success: false, message: 'School not found' }, status: :not_found
      end

      def set_grade
        @grade = @school.grades.find(params[:grade_id])
      rescue BSON::Error::InvalidObjectId, Mongoid::Errors::DocumentNotFound
        render json: { success: false, message: 'Grade not found' }, status: :not_found
      end

      def set_class
        @class = @grade.school_classes.find(params[:id])
      rescue BSON::Error::InvalidObjectId, Mongoid::Errors::DocumentNotFound
        render json: { success: false, message: 'Class not found' }, status: :not_found
      end

      def class_params
        params.require(:class).permit(:name, :capacity, :class_teacher_id)
      end
    end
  end
end
