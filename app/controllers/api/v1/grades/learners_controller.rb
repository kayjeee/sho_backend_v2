module Api
  module V1
    module Grades
      class LearnersController < Api::V1::BaseController
        def index
          grade_id = params[:grade_id]
          school_id = params[:school_id] || params[:schoolId]

          if grade_id.blank?
            return render json: { success: false, error: "Grade identifier is required." }, status: :bad_request
          end

          begin
            @grade = Grade.find(grade_id)
          rescue Mongoid::Errors::DocumentNotFound, Mongoid::Errors::InvalidFind
            return render json: { success: false, error: "Grade not found." }, status: :not_found
          end

          # The production database collection strictly stores relation values as 'gradeId' (camelCase string)
          query = { "gradeId" => @grade.id.to_s }

          # Query school_id as a string if provided
          if school_id.present?
            query["school_id"] = school_id.to_s
          end

          # Fetch using the Mongo Ruby driver and safely convert/instantiate back to Mongoid model instances
          raw_docs = Learner.collection.find(query)
          @learners = raw_docs.map { |doc| Learner.instantiate(doc) }

          render json: {
            success: true,
            total: @learners.size,
            learners: @learners.map { |learner| serialize_learner(learner) }
          }, status: :ok
        end

        private

        def serialize_learner(learner)
          contact = contact_for(learner)

          {
            id: learner.id.to_s,
            firstName: learner.try(:firstName) || learner.try(:first_name),
            lastName: learner.try(:lastName) || learner.try(:last_name),
            gender: learner.gender,
            accessionNumber: learner.try(:accessionNumber) || learner.try(:accession_number),
            gradeId: @grade.id.to_s,
            school_id: learner.school_id.to_s,
            parent_id: learner.try(:parent_id)&.to_s || nil,
            status: learner.try(:status) || "active",
            # Phone numbers: top-level `phone` (best available number) plus the full nested `contact`
            phone: contact[:phone].presence || contact[:whatsapp].presence ||
                   contact[:tel_emergency].presence || contact[:tel_home].presence,
            contact: contact
          }
        end

        # Reads from the raw attributes so it works whether the document stores
        # snake_case (phone, tel_home, tel_emergency) or camelCase (telHome, telEmergency).
        def contact_for(learner)
          attrs = learner.attributes

          {
            phone: attrs["phone"].presence,
            whatsapp: attrs["whatsapp"].presence,
            tel_home: (attrs["tel_home"] || attrs["telHome"]).presence,
            tel_emergency: (attrs["tel_emergency"] || attrs["telEmergency"]).presence,
            telegram: attrs["telegram"].presence
          }
        end
      end
    end
  end
end