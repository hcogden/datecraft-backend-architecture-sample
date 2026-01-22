# frozen_string_literal: true

class DateSuggestionService
  include HTTParty
  base_uri 'https://api.openai.com/v1'
  default_timeout 30
  
  OPENAI_MODEL = 'gpt-4o-mini-2024-07-18'
  TEMPERATURE = 0.7
  VALID_CATEGORIES = %w[dining outdoor entertainment adventure relaxation cultural].freeze

  def initialize(user_profile, category = nil)
    @user_profile = user_profile
    @category = category
    api_key = ENV['OPENAI_API_KEY']
    
    raise "OpenAI API key not found!" if api_key.nil? || api_key.empty?
    
    @headers = {
      'Authorization' => "Bearer #{api_key}",
      'Content-Type' => 'application/json'
    }
  end

  def generate_suggestions
    raise "User profile not found!" if @user_profile.nil?
    
    prompt = generate_prompt
    Rails.logger.info "Generated prompt: #{prompt}"
  
    response = self.class.post('/chat/completions',
      headers: @headers,
      body: {
        model: OPENAI_MODEL,
        messages: [{
          role: 'user',
          content: prompt
        }],
        temperature: TEMPERATURE
      }.to_json
    )
  
    Rails.logger.info "OpenAI API response: #{response.body}"
    
    parse_response(response.body)
  rescue => e
    Rails.logger.error "OpenAI API error: #{e.message}"
    []
  end

  private

  def generate_prompt
    allergies = YAML.safe_load(@user_profile.allergies, permitted_classes: [Symbol]) rescue []
    interests = YAML.safe_load(@user_profile.interests, permitted_classes: [Symbol]) rescue []
    time_context = build_time_context
    duration_context = build_duration_context
    category_context = if @category
      "Category Preference: Please suggest #{@category} activities."
    else
      "Please suggest activities from different categories. Avoid suggesting the same activity type repeatedly."
    end

    <<~PROMPT
      Based on the following user profile, suggest #{suggestions_count} unique and creative date ideas:
      Name: #{@user_profile.name}
      Location: #{@user_profile.location}
      #{time_context}
      #{duration_context}
      #{category_context}
      Dietary Preferences: #{@user_profile.dietary_preferences&.join(', ') || 'None'}
      #{'Allergies: ' + allergies.join(', ') if allergies.any?}
      #{'Interests: ' + interests.join(', ') if interests.any?}
      #{'Budget: ' + @user_profile.budget.to_s if @user_profile.budget}

      Please make each suggestion different and creative. Consider local events, seasonal activities, and unique experiences.
      Avoid suggesting the same activities repeatedly.

      Please provide the response in the following JSON format:
      [
        {
          "title": "Date idea title",
          "description": "Brief description",
          "estimated_cost": "Estimated cost in USD",
          "location": "Suggested location",
          "category": "Primary category (MUST be one of: dining, outdoor, entertainment, adventure, relaxation, cultural)",
          "recommended_start_time": "Suggested start time (optional)",
          "duration": "Estimated duration in hours",
          "sequence": "If multiple activities, position in sequence (1, 2, 3)"
        }
      ]
      
      Note: The category MUST be exactly one of: dining, outdoor, entertainment, adventure, relaxation, or cultural.
      Any other categories will be rejected. Make sure each location suggested is not permanently closed.
      #{build_special_instructions}
    PROMPT
  end

  def build_time_context
    return "Time Preference: Flexible" unless @user_profile.time_preference

    case @user_profile.time_preference
    when 'morning'
      "Time Preference: Morning (6am-11am). Please suggest activities during these hours."
    when 'afternoon'
      "Time Preference: Afternoon (11am-5pm). Please suggest activities during these hours."
    when 'evening'
      "Time Preference: Evening (5pm-11pm). Please suggest activities during these hours."
    else
      "Time Preference: Flexible"
    end
  end

  def build_duration_context
    case @user_profile.duration_preference
    when 'quick'
      "Duration: Looking for a shorter date (1-2 hours)"
    when 'medium'
      "Duration: Planning for a medium-length date (2-4 hours)"
    when 'extended'
      "Duration: Planning for a longer date experience (4+ hours)"
    else
      "Duration: Flexible"
    end
  end

  def suggestions_count
    case @user_profile.duration_preference
    when 'extended'
      3  # Multiple activities for longer dates
    else
      1  # Single activity for shorter dates
    end
  end

  def build_special_instructions
    instructions = []
    
    if @user_profile.duration_preference == 'extended'
      instructions << "Create a sequence of activities that flow well together"
      instructions << "Ensure locations are reasonably close to each other. Find specific locations." \
      "Do not be general. Look specifically for new and interesting activities and locations/events when applicable"
      instructions << "Include transition times between activities"
    end

    if @user_profile.preferred_date.present?
      instructions << "Consider business hours for the suggested date and time"
    end

    instructions.join(". ")
  end

  def parse_response(body)
    Rails.logger.info "Parsing response body: #{body}"
    parsed = JSON.parse(body)
    return [] if parsed['error']
  
    content = parsed.dig('choices', 0, 'message', 'content')
    Rails.logger.info "Extracted content: #{content}"
  
    # Remove the surrounding ```json and ``` if present
    content = content.gsub(/```json\n|\n```/, '')
  
    suggestions = JSON.parse(content) rescue []
    Rails.logger.info "Parsed suggestions: #{suggestions}"
  
    # Handle single suggestions that contain multiple sequences
    suggestions.flat_map do |suggestion|
      if suggestion['sequence'].to_s.include?(',') || suggestion['sequence'].to_s.include?('for')
        split_sequenced_suggestion(suggestion)
      else
        format_suggestion(suggestion)
      end
    rescue => e
      Rails.logger.error "Error parsing suggestion: #{e.message}"
      nil
    end.compact
  end

  private

  def split_sequenced_suggestion(suggestion)
    # Split description into separate activities
    if suggestion['description'].include?(' followed by ')
      activities = suggestion['description'].split(' followed by ').map(&:strip)
      
      activities.map.with_index do |activity, index|
        {
          title: activity.split('.').first,
          description: activity,
          location: suggestion['location'].split(' & ')[index] || suggestion['location'],
          budget: map_cost_to_budget(suggestion['estimated_cost']),
          category: infer_category(activity),
          recommended_start_time: extract_time_for_sequence(suggestion['recommended_start_time'], index + 1),
          duration: extract_duration_for_sequence(suggestion['duration'], activities.length),
          sequence: index + 1
        }
      end
    else
      [format_suggestion(suggestion)]
    end
  end

  def format_suggestion(suggestion)
    # Parse multiple categories and select the first valid one
    categories = suggestion['category'].to_s.split(/[,\s]+/).map(&:downcase)
    valid_category = categories.find { |cat| VALID_CATEGORIES.include?(cat) } || 'entertainment'

    # Add randomization to start times if none provided
    if suggestion['recommended_start_time'].blank?
      suggestion['recommended_start_time'] = generate_random_start_time(valid_category)
    end

    {
      title: suggestion['title'],
      description: suggestion['description'],
      location: suggestion['location'],
      budget: map_cost_to_budget(suggestion['estimated_cost']),
      category: valid_category,
      recommended_start_time: suggestion['recommended_start_time'],
      duration: suggestion['duration']&.to_f,
      sequence: suggestion['sequence']&.to_i || 1
    }
  end

  def extract_time_for_sequence(time_str, sequence)
    return nil unless time_str
    
    if time_str.include?(' & ') || time_str.include?(',')
      times = time_str.split(/[&,]\s*/).map(&:strip)
      times[sequence - 1] || times.last
    else
      times = time_str.scan(/\d{1,2}:\d{2}\s*(?:AM|PM)/i)
      times.any? ? (times[sequence - 1] || times.last) : time_str
    end
  end

  def extract_duration_for_sequence(duration_str, total_sequences)
    total_duration = duration_str.to_s.scan(/\d+/).first.to_f
    (total_duration / total_sequences).round(1)
  end

  def map_cost_to_budget(cost)
    return 'free' if cost.nil? || cost.to_s.downcase.include?('free')
    
    amount = cost.to_s.scan(/\d+/).first.to_i
    case amount
    when 0 then 'free'
    when 1..50 then 'low'
    when 51..100 then 'medium'
    else 'high'
    end
  end

  def infer_category(description)
    return 'dining' unless description
    case description.downcase
    when /food|restaurant|cafe|dinner|lunch|breakfast|brunch|cook/
      'dining'
    when /park|beach|hike|nature|garden|outdoor/
      'outdoor'
    when /movie|theater|concert|show|music|performance/
      'entertainment'
    when /class|museum|art|gallery|historic|culture/
      'cultural'
    when /spa|massage|relax|wellness/
      'relaxation'
    else
      'entertainment'
    end
  end

  def generate_random_start_time(category)
    case category
    when 'dining'
      ['11:30 AM', '12:30 PM', '6:00 PM', '7:00 PM', '7:30 PM'].sample
    when 'outdoor'
      ['9:00 AM', '10:00 AM', '3:00 PM', '4:00 PM'].sample
    when 'cultural'
      ['10:00 AM', '1:00 PM', '2:00 PM', '3:00 PM'].sample
    when 'entertainment'
      ['2:00 PM', '5:00 PM', '7:00 PM', '8:00 PM'].sample
    when 'relaxation'
      ['10:00 AM', '2:00 PM', '4:00 PM'].sample
    when 'adventure'
      ['9:00 AM', '10:00 AM', '2:00 PM'].sample
    end
  end
end
