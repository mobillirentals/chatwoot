class AddCaptainSentimentToConversations < ActiveRecord::Migration[7.0]
  def change
    add_column :conversations, :captain_sentiment, :integer
    add_column :conversations, :captain_sentiment_updated_at, :datetime
  end
end
