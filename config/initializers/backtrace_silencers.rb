# Be sure to restart your server when you modify this file.

# Suppress framework/gem and rbenv lines in console log backtraces to keep logs clean
Rails.backtrace_cleaner.add_silencer { |line| line =~ /gems|\.rbenv|lib\/ruby|usr\/local/ }
