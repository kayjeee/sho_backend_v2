# app/services/user_services/parent_linkage_service.rb
module UserServices
  class ParentLinkageService
    def initialize(user:, learner_ids:)
      @user = user
      @learner_ids = learner_ids
    end

    def call
      link_learners
      @user
    end

    private

    def link_learners
      return unless @user && @learner_ids.any?

      learners = Learner.where(:id.in => @learner_ids)
      learners.each do |learner|
        unless learner.parent_ids.include?(@user.id.to_s)
          learner.parent_ids << @user.id.to_s
          learner.save
        end
      end
    end
  end
end
