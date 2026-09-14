module Api
  module V1
    class ClassesController < Api::V1::BaseController
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
        teacher_id = params[:teacher_id] || params[:teacherId]
        role = params[:role] # 'class_teacher' or 'subject_teacher'
        subject_id = params[:subject_id] || params[:subjectId] # Required for subject_teacher

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
          class: class_json(@school_class, detailed: true)
        }
      end

      # POST /api/v1/schools/:school_id/grades/:grade_id/classes/:id/move_learner
      def move_learner
        learner_id = params[:learner_id] || params[:learnerId]
        payload_target_class_id = params[:target_class_id] || params[:targetClassId]

        if learner_id.blank?
          return render json: { success: false, error: "Learner identifier (learner_id) is missing." }, status: :bad_request
        end

        begin
          @learner = Learner.find(learner_id)
        rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId, Mongoid::Errors::InvalidFind
          return render json: { success: false, error: "Learner with ID #{learner_id} not found." }, status: :not_found
        end

        learner_id_str = learner_id.to_s
        bson_learner_id = BSON::ObjectId.legal?(learner_id_str) ? BSON::ObjectId.from_string(learner_id_str) : nil

        if payload_target_class_id.present?
          source_class = @school_class
          begin
            target_class = @grade.school_classes.find(payload_target_class_id)
          rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId, Mongoid::Errors::InvalidFind
            return render json: { success: false, error: "Target class not found" }, status: :not_found
          end
        else
          target_class = @school_class
          source_class_id = @learner.school_class_id
          if source_class_id.present?
            source_class = SchoolClass.find(source_class_id) rescue nil
          end
        end

        if source_class && source_class.id == target_class.id
          return render json: { success: false, error: "Learner is already in the target class" },
                        status: :unprocessable_entity
        end

        if source_class
          existing_ids = source_class.learner_ids.map(&:to_s)
          unless existing_ids.include?(learner_id_str)
            return render json: { success: false, error: "Learner not found in source class" },
                          status: :unprocessable_entity
          end
        end

        if target_class.full?
          return render json: { success: false, error: "Target class is at full capacity" },
                        status: :unprocessable_entity
        end

        if source_class
          source_class.pull(learner_ids: bson_learner_id || learner_id_str)
          source_class.pull(learner_ids: learner_id_str)
        end

        target_class.add_to_set(learner_ids: learner_id_str)

        @learner.update(
          grade_id: @grade.id.to_s,
          school_class_id: target_class.id.to_s
        )

        render json: {
          success: true,
          message: "Learner moved successfully",
          source_class: source_class ? class_json(source_class.reload, detailed: true) : nil,
          target_class: class_json(target_class.reload, detailed: true)
        }
      end

      # GET /api/v1/schools/:school_id/grades/:grade_id/classes/:id/learners
      def learners
        raw_learner_ids = Array(@school_class.learner_ids).map(&:to_s)
        learner_bsons = raw_learner_ids.map { |id| BSON::ObjectId.legal?(id) ? BSON::ObjectId.from_string(id) : nil }.compact

        docs = Learner.collection.find(
          "_id" => { "$in" => (raw_learner_ids + learner_bsons).uniq }
        ).to_a

        learners = docs.map { |d| Learner.instantiate(d) }

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
        school_param = params[:school_id] || params[:schoolId]
        @school = find_school_by_id_or_slug(school_param)

        if @school.nil? && params[:grade_id].present?
          begin
            @grade = Grade.find(params[:grade_id])
            @school = @grade.school if @grade
          rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
            # Handled in set_grade
          end
        end

        unless @school
          render json: { success: false, error: "School not found" }, status: :not_found and return
        end
      rescue AmbiguousSchoolError => e
        render json: {
          success: false,
          error: e.message,
          matching_schools: e.matching_schools.map { |s| { id: s.id.to_s, name: s.schoolName } }
        }, status: :conflict and return
      rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
        render json: { success: false, error: "School not found" }, status: :not_found and return
      end

      def set_grade
        return unless @school
        @grade = Grade.find(params[:grade_id])
        if @grade.school_id.to_s != @school.id.to_s
          render json: { success: false, error: "Grade not found" }, status: :not_found and return
        end
      rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
        render json: { success: false, error: "Grade not found" }, status: :not_found and return
      end

      def set_class
        return unless @grade
        @school_class = @grade.school_classes.find(params[:id])
      rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
        render json: { success: false, error: "Class not found" }, status: :not_found and return
      end

      def class_params
        source = params[:class].presence || params
        source.permit(:name, :capacity, :class_teacher_id).tap do |p|
          p[:class_teacher_id] = nil if p[:class_teacher_id].blank?
          p[:capacity] = 40 if p[:capacity].blank?
        end
      end

      def resolve_teacher_name(teacher_id)
        return nil if teacher_id.blank?

        t_str = teacher_id.to_s
        t_bson = BSON::ObjectId.legal?(t_str) ? BSON::ObjectId.from_string(t_str) : nil

        u_doc = User.collection.find(
          "$or" => [
            { "_id" => { "$in" => [t_str, t_bson].compact } },
            { "auth0_id" => t_str }
          ]
        ).first

        return nil unless u_doc

        user = User.instantiate(u_doc)
        user.try(:full_name) || user.try(:name) || "#{u_doc['name'] || u_doc['display_name']}".strip
      rescue => e
        Rails.logger.error "❌ Error resolving teacher_name for teacher #{teacher_id}: #{e.message}"
        nil
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
          grade_name: @grade&.name || school_class.grade&.name,
          capacity: school_class.capacity,
          current_learners: school_class.learner_ids.count,
          utilization: "#{school_class.learner_ids.count}/#{school_class.capacity}",
          utilization_percentage: utilization_percentage
        }

        if detailed
          json[:class_teacher_id] = school_class.class_teacher_id
          json[:class_teacher_name] = resolve_teacher_name(school_class.class_teacher_id)
          json[:subject_teachers] = school_class.subject_teacher_ids
          json[:learner_ids] = school_class.learner_ids.map(&:to_s)
          json[:school_name] = @school&.schoolName
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
