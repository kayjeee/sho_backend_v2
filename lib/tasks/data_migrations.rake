namespace :data_migrations do
  desc "Convert school_id from String to BSON::ObjectId for all learners"
  task convert_school_ids: :environment do
    puts "Starting conversion of school_ids..."
    learners_to_update = Learner.where(:school_id.type => String)
    count = learners_to_update.count
    puts "Found #{count} learners with string school_ids."

    learners_to_update.each do |learner|
      begin
        learner.set(school_id: BSON::ObjectId(learner.school_id))
      rescue BSON::ObjectId::Invalid => e
        puts "Could not convert school_id for learner #{learner.id}: #{e.message}"
      end
    end

    puts "Finished conversion."
  end

  desc "Backfill accession_number for learners where it is nil"
  task backfill_accession_numbers: :environment do
    puts "Starting to backfill accession_numbers..."
    learners_by_school = Learner.where(accession_number: nil).group_by(&:school_id)

    learners_by_school.each do |school_id, learners|
      puts "Processing school #{school_id}..."
      learners.each_with_index do |learner, i|
        # Find the highest existing learner number for the school to avoid collisions
        highest_number = Learner.where(school_id: school_id, :accession_number.ne => nil).map { |l| l.accession_number.gsub(/[^0-9]/, '').to_i }.max || 0
        new_number = "L#{highest_number + i + 1}"
        learner.set(accession_number: new_number)
      end
    end

    puts "Finished backfilling accession_numbers."
  end
end
