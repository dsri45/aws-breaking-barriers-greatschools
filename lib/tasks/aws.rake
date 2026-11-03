namespace :aws do
  desc "Verify the EC2 role can invoke Bedrock and read the private OpenSearch domain"
  task smoke: :environment do
    response = GuidedSearch::Bedrock.new.converse(
      messages: [{ role: "user", content: [{ text: "Reply with OK." }] }],
      inference_config: { max_tokens: 16 }
    )
    abort "Bedrock returned no text" unless response.output&.message&.content&.any? { |item| item.text.present? }
    puts "Bedrock Converse OK"

    search = GuidedSearch::OpenSearch.new.request("GET", "/")
    puts "OpenSearch #{search.fetch("version").fetch("number")} OK"
  end
end
