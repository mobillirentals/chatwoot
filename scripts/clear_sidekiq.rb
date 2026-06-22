require 'sidekiq/api'
Sidekiq::RetrySet.new.clear
Sidekiq::DeadSet.new.clear
puts "Sidekiq retry/dead jobs cleared"
