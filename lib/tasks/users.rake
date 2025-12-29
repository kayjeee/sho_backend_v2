namespace :users do
  desc "Normalize all user roles to be lowercase and unique"
  task normalize_roles: :environment do
    puts "Starting role normalization for all users..."

    User.all.each do |user|
      original_roles = user.roles.dup
      normalized_roles = original_roles.map(&:downcase).uniq

      if original_roles != normalized_roles
        user.roles = normalized_roles
        if user.save(validate: false)
          puts "Normalized roles for user #{user.email} (ID: #{user.id}) from #{original_roles} to #{normalized_roles}"
        else
          puts "Failed to normalize roles for user #{user.email} (ID: #{user.id}). Errors: #{user.errors.full_messages.join(', ')}"
        end
      end
    end

    puts "Role normalization complete."
  end
end
