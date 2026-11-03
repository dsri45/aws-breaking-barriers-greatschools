namespace :data do
  desc "Ensure indexes exist, then load schools and programs from db/seeds"
  task load: :environment do
    GuidedSearch::Indexer.new.create_all
    counts = GuidedSearch::DataLoader.new.load_all
    puts "Loaded: #{counts.map { |name, count| "#{count} #{name}" }.join(', ')}"
  end

  desc "Drop, recreate, and reload both indexes from scratch"
  task reload: :environment do
    GuidedSearch::Indexer.new.recreate_all
    counts = GuidedSearch::DataLoader.new.load_all
    puts "Reloaded: #{counts.map { |name, count| "#{count} #{name}" }.join(', ')}"
  end
end
