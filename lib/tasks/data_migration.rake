# lib/tasks/data_migration.rake
namespace :data_migration do
  desc 'Migrates legacy parent information to the new parent_auth0_ids array in the Learner model.'
  task migrate_parent_links: :environment do
    puts 'Starting parent link migration...'

    learners_to_migrate = Learner.or(
      { 'parent_info.auth0_id'.exists => true, 'parent_info.auth0_id'.ne => '' },
      { :auth0Id.exists => true, :auth0Id.ne => '' },
      { :userAuth0Id.exists => true, :userAuth0Id.ne => '' }
    )

    migrated_count = 0
    error_count = 0

    puts "Found #{learners_to_migrate.count} learners to migrate."

    learners_to_migrate.each do |learner|
      begin
        auth0_ids = Set.new(learner.parent_auth0_ids || [])
        legacy_id_1 = learner.try(:parent_info)&.[]('auth0_id')
        legacy_id_2 = learner.try(:auth0Id)
        legacy_id_3 = learner.try(:userAuth0Id)

        auth0_ids.add(legacy_id_1) if legacy_id_1.present?
        auth0_ids.add(legacy_id_2) if legacy_id_2.present?
        auth0_ids.add(legacy_id_3) if legacy_id_3.present?

        new_ids = auth0_ids.to_a

        if learner.parent_auth0_ids != new_ids
          learner.update!(parent_auth0_ids: new_ids)
          puts "  - Migrated learner #{learner.id}. New IDs: #{new_ids.join(', ')}"
          migrated_count += 1
        else
          puts "  - Learner #{learner.id} already up-to-date. Skipping."
        end

      rescue StandardError => e
        puts "  - ERROR migrating learner #{learner.id}: #{e.message}"
        error_count += 1
      end
    end

    puts "\nMigration complete."
    puts "Successfully migrated: #{migrated_count} learners."
    puts "Failed to migrate: #{error_count} learners."
  end

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
        highest_number = Learner.where(school_id: school_id, :accession_number.ne => nil).map { |l| l.accession_number.gsub(/[^0-9]/, '').to_i }.max || 0
        new_number = "L#{highest_number + i + 1}"
        learner.set(accession_number: new_number)
      end
    end

    puts "Finished backfilling accession_numbers."
  end
end
