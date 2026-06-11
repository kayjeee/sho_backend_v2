module GradeServices
  class ListGradesService
    attr_reader :school, :page, :per_page, :filters, :errors

    ServiceResult = Struct.new(:success, :errors, :grades, :pagination, keyword_init: true)

    def initialize(school:, page: 1, per_page: 20, filters: {})
      @school = school
      @page = (page.to_i > 0 ? page.to_i : 1)
      @per_page = (per_page.to_i > 0 ? per_page.to_i : 20)
      @filters = filters || {}
      @errors = []
    end

    def call
      return create_error_result unless school.present?

      grades = fetch_grades_with_learner_counts
      ServiceResult.new(success: true, grades: grades, pagination: pagination_metadata)
    end

    private

    # Fetch grades and attach learner counts
    def fetch_grades_with_learner_counts
      criteria = school.grades.order_by(name: :asc)
      # Apply filters if needed, e.g.:
      # criteria = criteria.where(status: filters[:status].to_i) if filters[:status].present?

      grades = criteria.skip((page - 1) * per_page).limit(per_page).to_a

      # Get the grade IDs currently loaded
      grade_ids = grades.map(&:id)

      # Aggregate to count active learners per grade in a single MongoDB query
      counts = Learner.collection.aggregate([
        { '$match' => { 'gradeId' => { '$in' => grade_ids.map(&:to_s) }, 'status' => 0 } }, # Active learners only
        { '$group' => { '_id' => '$gradeId', 'count' => { '$sum' => 1 } } }
      ]).to_a

      counts_map = counts.each_with_object({}) { |doc, h| h[doc['_id']] = doc['count'] }

      # Attach learnerCount dynamically to each grade instance (not persisted)
      grades.each do |grade|
        learner_count = counts_map[grade.id] || 0
        # Define a getter method dynamically or set instance var
        grade.instance_variable_set(:@learner_count, learner_count)
        def grade.learnerCount
          @learner_count || 0
        end
      end

      grades
    end

    def pagination_metadata
      total = school.grades.count
      total_pages = (total.to_f / per_page).ceil
      {
        current_page: page,
        per_page: per_page,
        total_pages: total_pages,
        total_count: total
      }
    end

    def create_error_result
      ServiceResult.new(success: false, errors: ['School must be provided'], grades: [], pagination: {})
    end
  end
end
