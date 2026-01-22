require 'rails_helper'

RSpec.describe DateSuggestionService, type: :service do
  let(:user_profile) { create(:user_profile, location: 'San Francisco, CA') }
  let(:service) { described_class.new(user_profile) }
  
  # Sample OpenAI response for testing
  let(:openai_success_response) do
    {
      'choices' => [{
        'message' => {
          'content' => <<~JSON
            ```json
            [
              {
                "title": "Sunset Dinner at The Cliff House",
                "description": "Enjoy fresh seafood with ocean views",
                "estimated_cost": "$75",
                "location": "The Cliff House, San Francisco",
                "category": "dining",
                "recommended_start_time": "7:00 PM",
                "duration": "2",
                "sequence": 1
              }
            ]
            ```
          JSON
        }
      }]
    }.to_json
  end
  
  let(:openai_extended_response) do
    {
      'choices' => [{
        'message' => {
          'content' => <<~JSON
            ```json
            [
              {
                "title": "Morning Hike at Lands End",
                "description": "Scenic coastal trail with Golden Gate views",
                "estimated_cost": "Free",
                "location": "Lands End Trail, San Francisco",
                "category": "outdoor",
                "recommended_start_time": "9:00 AM",
                "duration": "2",
                "sequence": 1
              },
              {
                "title": "Brunch at Zazie",
                "description": "French bistro with outdoor garden seating",
                "estimated_cost": "$45",
                "location": "Zazie, Cole Valley",
                "category": "dining",
                "recommended_start_time": "11:30 AM",
                "duration": "1.5",
                "sequence": 2
              },
              {
                "title": "Visit SFMOMA",
                "description": "Modern art museum with rotating exhibitions",
                "estimated_cost": "$25",
                "location": "SFMOMA, 151 3rd St",
                "category": "cultural",
                "recommended_start_time": "2:00 PM",
                "duration": "2.5",
                "sequence": 3
              }
            ]
            ```
          JSON
        }
      }]
    }.to_json
  end
  
  let(:openai_error_response) do
    {
      'error' => {
        'message' => 'Invalid API key',
        'type' => 'invalid_request_error'
      }
    }.to_json
  end

  describe '#initialize' do
    context 'with valid API key' do
      before do
        allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return('test-api-key')
      end
      
      it 'creates a service instance' do
        expect(service).to be_a(DateSuggestionService)
      end
      
      it 'sets the user profile' do
        expect(service.instance_variable_get(:@user_profile)).to eq(user_profile)
      end
      
      it 'sets proper headers' do
        headers = service.instance_variable_get(:@headers)
        expect(headers['Authorization']).to eq('Bearer test-api-key')
        expect(headers['Content-Type']).to eq('application/json')
      end
    end
    
    context 'without API key' do
      before do
        allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return(nil)
      end
      
      it 'raises an error' do
        expect { described_class.new(user_profile) }.to raise_error('OpenAI API key not found!')
      end
    end
    
    context 'with category filter' do
      let(:service) { described_class.new(user_profile, 'dining') }
      
      it 'stores the category' do
        expect(service.instance_variable_get(:@category)).to eq('dining')
      end
    end
  end

  describe '#generate_suggestions' do
    before do
      allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return('test-api-key')
    end
    
    context 'with successful API response' do
      before do
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(status: 200, body: openai_success_response)
      end
      
      it 'returns an array of suggestions' do
        suggestions = service.generate_suggestions
        expect(suggestions).to be_an(Array)
        expect(suggestions.length).to eq(1)
      end
      
      it 'parses suggestion attributes correctly' do
        suggestions = service.generate_suggestions
        suggestion = suggestions.first
        
        expect(suggestion[:title]).to eq('Sunset Dinner at The Cliff House')
        expect(suggestion[:description]).to eq('Enjoy fresh seafood with ocean views')
        expect(suggestion[:location]).to eq('The Cliff House, San Francisco')
        expect(suggestion[:category]).to eq('dining')
        expect(suggestion[:budget]).to eq('medium')
        expect(suggestion[:duration]).to eq(2.0)
      end
    end
    
    context 'with extended duration preference' do
      let(:user_profile) { create(:user_profile, :extended_date, location: 'San Francisco, CA') }
      
      before do
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(status: 200, body: openai_extended_response)
      end
      
      it 'returns multiple suggestions in sequence' do
        suggestions = service.generate_suggestions
        expect(suggestions.length).to eq(3)
        expect(suggestions.map { |s| s[:sequence] }).to eq([1, 2, 3])
      end
      
      it 'includes different categories' do
        suggestions = service.generate_suggestions
        categories = suggestions.map { |s| s[:category] }
        expect(categories).to include('outdoor', 'dining', 'cultural')
      end
    end
    
    context 'with API error' do
      before do
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(status: 401, body: openai_error_response)
      end
      
      it 'returns an empty array' do
        suggestions = service.generate_suggestions
        expect(suggestions).to eq([])
      end
    end
    
    context 'with network timeout' do
      before do
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_timeout
      end
      
      it 'handles timeout gracefully' do
        expect(Rails.logger).to receive(:error).with(/OpenAI API error/)
        suggestions = service.generate_suggestions
        expect(suggestions).to eq([])
      end
    end
  end

  describe 'prompt generation' do
    before do
      allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return('test-api-key')
    end
    
    context 'with basic profile' do
      it 'includes user name and location' do
        prompt = service.send(:generate_prompt)
        expect(prompt).to include(user_profile.name)
        expect(prompt).to include(user_profile.location)
      end
      
      it 'requests correct number of suggestions' do
        prompt = service.send(:generate_prompt)
        expect(prompt).to include('suggest 1 unique and creative date ideas')
      end
    end
    
    context 'with time preferences' do
      let(:user_profile) { create(:user_profile, :evening_preference) }
      
      it 'includes time preference in prompt' do
        prompt = service.send(:generate_prompt)
        expect(prompt).to include('Evening (5pm-11pm)')
      end
    end
    
    context 'with dietary restrictions' do
      let(:user_profile) { create(:user_profile, :with_dietary_restrictions) }
      
      it 'includes dietary preferences' do
        prompt = service.send(:generate_prompt)
        expect(prompt).to include('Vegetarian')
        expect(prompt).to include('Gluten-free')
      end
      
      it 'includes allergies' do
        prompt = service.send(:generate_prompt)
        expect(prompt).to include('Peanuts')
        expect(prompt).to include('Shellfish')
      end
    end
    
    context 'with interests' do
      let(:user_profile) { create(:user_profile, :with_interests) }
      
      it 'includes user interests' do
        prompt = service.send(:generate_prompt)
        expect(prompt).to include('Hiking')
        expect(prompt).to include('Museums')
      end
    end
    
    context 'with category filter' do
      let(:service) { described_class.new(user_profile, 'outdoor') }
      
      it 'includes category preference' do
        prompt = service.send(:generate_prompt)
        expect(prompt).to include('outdoor activities')
      end
    end
    
    context 'with extended duration' do
      let(:user_profile) { create(:user_profile, :extended_date) }
      
      it 'requests multiple activities' do
        prompt = service.send(:generate_prompt)
        expect(prompt).to include('suggest 3 unique and creative date ideas')
      end
      
      it 'includes special instructions for sequences' do
        prompt = service.send(:generate_prompt)
        expect(prompt).to include('sequence of activities')
        expect(prompt).to include('flow well together')
      end
    end
  end

  describe 'budget mapping' do
    before do
      allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return('test-api-key')
    end
    
    it 'maps free correctly' do
      result = service.send(:map_cost_to_budget, 'Free')
      expect(result).to eq('free')
    end
    
    it 'maps low budget (1-50)' do
      result = service.send(:map_cost_to_budget, '$25')
      expect(result).to eq('low')
    end
    
    it 'maps medium budget (51-100)' do
      result = service.send(:map_cost_to_budget, '$75')
      expect(result).to eq('medium')
    end
    
    it 'maps high budget (100+)' do
      result = service.send(:map_cost_to_budget, '$150')
      expect(result).to eq('high')
    end
  end

  describe 'category inference' do
    before do
      allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return('test-api-key')
    end
    
    it 'infers dining category' do
      result = service.send(:infer_category, 'Visit a restaurant for dinner')
      expect(result).to eq('dining')
    end
    
    it 'infers outdoor category' do
      result = service.send(:infer_category, 'Hike in the park')
      expect(result).to eq('outdoor')
    end
    
    it 'infers entertainment category' do
      result = service.send(:infer_category, 'Watch a movie at the theater')
      expect(result).to eq('entertainment')
    end
    
    it 'infers cultural category' do
      result = service.send(:infer_category, 'Visit the art museum')
      expect(result).to eq('cultural')
    end
    
    it 'defaults to entertainment for unknown' do
      result = service.send(:infer_category, 'Some random activity')
      expect(result).to eq('entertainment')
    end
  end

  describe 'constants' do
    it 'has correct OpenAI model' do
      expect(DateSuggestionService::OPENAI_MODEL).to eq('gpt-4o-mini-2024-07-18')
    end
    
    it 'has valid categories' do
      expect(DateSuggestionService::VALID_CATEGORIES).to eq(%w[dining outdoor entertainment adventure relaxation cultural])
    end
    
    it 'has temperature setting' do
      expect(DateSuggestionService::TEMPERATURE).to eq(0.7)
    end
  end
end
