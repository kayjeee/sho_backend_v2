module Api
  module V1
    module Grades
      class LearnersController < Api::V1::BaseController
        def index
          grade_id_param = params[:grade_id]
          school_id_param = params[:school_id] || params[:schoolId]

          if grade_id_param.blank?
            return render json: { success: true, total: 0, learners: [] }
          end

          # Prepare possible values for the IDs (support both String and BSON)
          def get_possible_ids(id_str)
            return [] if id_str.blank?
            ids = [id_str.to_s]
            ids << BSON::ObjectId.from_string(id_str) if BSON::ObjectId.legal?(id_str)
            ids.uniq
          end

          grade_ids = get_possible_ids(grade_id_param)
          school_ids = get_possible_ids(school_id_param)

          # Strategy 1: Direct lookup on Learner collection (Legacy & Convenience)
          # We search across gradeId and grade_id fields, and support both String and BSON types.
          direct_criteria = {
            "$or" => [
              { gradeId: { "$in" => grade_ids } },
              { grade_id: { "$in" => grade_ids } }
            ]
          }

          if school_ids.any?
            direct_criteria[:school_id] = { "$in" => school_ids }
          end

          learners = Learner.where(direct_criteria).to_a

          # Strategy 2: Hierarchy lookup (Grade -> Classes -> Learner IDs)
          # This follows the new multi-tier architecture
          classes_criteria = { grade_id: { "$in" => grade_ids } }
          classes = SchoolClass.where(classes_criteria)

          learner_ids_from_classes = classes.flat_map(&:learner_ids).compact.uniq

          if learner_ids_from_classes.any?
            # Support learner IDs being either String or BSON in the learner_ids array
            search_ids = learner_ids_from_classes.map(&:to_s)
            learner_ids_from_classes.each do |id|
              search_ids << BSON::ObjectId.from_string(id.to_s) if BSON::ObjectId.legal?(id.to_s)
            end
            search_ids.uniq!

            class_learners = Learner.where(:_id.in => search_ids).to_a
            learners = (learners + class_learners).uniq { |l| l.id.to_s }
          end

          # Strategy 3: School-wide lookup if no grade matches found yet
          # Some data might not have gradeId or grade_id set correctly
          if learners.empty? && school_ids.any?
            # Find any learner in the school
            learners = Learner.where(school_id: { "$in" => school_ids }).to_a
          end

          # Serialize output using model's to_api_hash if available, or custom snapshot-friendly hash
          render json: {
            success: true,
            total: learners.count,
            learners: learners.map { |l|
              {
                id: l.id.to_s,
                firstName: l.try(:firstName) || l.try(:first_name),
                lastName: l.try(:lastName) || l.try(:last_name),
                gender: l.gender,
                accessionNumber: l.try(:accessionNumber) || l.try(:accession_number),
                schoolName: l.try(:schoolName) || l.try(:school_name),
                schoolEmail: l.try(:schoolEmail),
                userEmail: l.try(:userEmail),
                province: l.try(:province),
                auth0Id: l.try(:auth0Id) || l.try(:auth0_id),
                gradeId: l.try(:gradeId) || l.try(:grade_id)&.to_s,
                school_id: l.try(:school_id)&.to_s,
                status: l.try(:status) || "active"
              }
            }
          }, status: :ok
        end
      end
    end
  end
end
