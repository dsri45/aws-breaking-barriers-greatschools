namespace :opensearch do
  desc "Create the schools and programs indexes (idempotent)"
  task create_indexes: :environment do
    created = GuidedSearch::Indexer.new.create_all
    puts created.empty? ? "All indexes already existed." : "Created: #{created.join(', ')}"
  end

  desc "Drop the schools and programs indexes (idempotent)"
  task drop_indexes: :environment do
    dropped = GuidedSearch::Indexer.new.drop_all
    puts dropped.empty? ? "No indexes to drop." : "Dropped: #{dropped.join(', ')}"
  end

  desc "Drop and recreate the schools and programs indexes"
  task recreate_indexes: :environment do
    GuidedSearch::Indexer.new.recreate_all
    puts "Recreated: #{GuidedSearch::Indexer::INDEXES.keys.join(', ')}"
  end

  desc "Show index existence and document counts"
  task status: :environment do
    indexer = GuidedSearch::Indexer.new
    GuidedSearch::Indexer::INDEXES.keys.each do |name|
      exists = indexer.exists?(name)
      puts "  #{name}: #{exists ? "exists (#{indexer.count(name)} docs)" : 'missing'}"
    end
  end
end
