class DateSuggestionsController < ApplicationController
  skip_before_action :authenticate_user!
  
  FEEDBACK_POSITIVE = 'positive'
  FEEDBACK_NEGATIVE = 'negative'

  def index
    @date_suggestions = DateSuggestion.all
    @date_suggestions = @date_suggestions.where(category: params[:category]) if params[:category].present?
    @date_suggestions = @date_suggestions.where(budget: params[:budget]) if params[:budget].present?
  end

  def show
    @date_suggestion = DateSuggestion.find(params[:id])
  end

  def save
    @saved_date = SavedDate.new(
      date_suggestion_id: params[:id],
      scheduled_for: params[:scheduled_for],
      user_id: request.remote_ip # Using ip_address as user_id
    )
    
    if @saved_date.save
      redirect_to saved_dates_path, notice: 'Date saved successfully!'
    else
      redirect_to date_suggestion_path(params[:id]), alert: 'Unable to save date.'
    end
  end

  def feedback
    @date_suggestion = DateSuggestion.find(params[:id])

    case params[:feedback]
    when FEEDBACK_POSITIVE
      redirect_to plan_date_suggestion_path(@date_suggestion)
    when FEEDBACK_NEGATIVE
      # Pass the original category if available
      redirect_to random_date_suggestion_path(@date_suggestion)
    end
  end
  
  def random
    # Get the current suggestion's ID and find its index in the session array
    current_suggestions = session[:current_suggestions] || []
    current_index = current_suggestions.index(params[:id].to_i)

    if current_index && current_index < current_suggestions.length - 1
      # Show the next suggestion in sequence
      next_suggestion = DateSuggestion.find(current_suggestions[current_index + 1])
      redirect_to date_suggestion_path(next_suggestion)
    else
      # If we're at the end, redirect to the index with the original category parameter
      category_param = session[:last_category_param]
      redirect_to date_suggestions_path(category: category_param), notice: "Those were all the suggestions! Generate more for new ideas."
    end
  end

  def generate 
    @user_profile = user_signed_in? ? current_user.user_profile : UserProfile.find_by(ip_address: request.remote_ip)
    
    unless @user_profile
      redirect_to date_suggestions_path, alert: 'User profile not found. Please complete your profile first.'
      return
    end

    # Validate preferred date
    return unless validate_future_date(params[:preferred_date], root_path)

    # Update user profile with form preferences
    @user_profile.update(
      preferred_date: params[:preferred_date],
      time_preference: params[:time_preference],
      duration_preference: params[:duration_preference]
    )

    # Store the category parameter in session for use in other actions
    session[:last_category_param] = params[:category] if params[:category].present?

    service = DateSuggestionService.new(@user_profile, params[:category])
    suggestions = service.generate_suggestions
  
    Rails.logger.info "Generated suggestions: #{suggestions.inspect}"
  
    if suggestions.is_a?(Array) && suggestions.any?
      parent_suggestion = nil
      
      created_suggestions = suggestions.map.with_index do |suggestion, index|
        date = DateSuggestion.create!(
          title: suggestion[:title],
          description: suggestion[:description],
          category: suggestion[:category].to_s.downcase,
          budget: suggestion[:budget],
          location: suggestion[:location],
          recommended_start_time: suggestion[:recommended_start_time],
          duration: suggestion[:duration],
          sequence: index + 1,
          parent_suggestion: index.zero? ? nil : parent_suggestion
        )
        parent_suggestion = date if index.zero?
        date
      end
      
      session[:current_suggestions] = created_suggestions.map(&:id)
      redirect_to date_suggestion_path(created_suggestions.first)
    else
      Rails.logger.error "No valid suggestions generated"
      redirect_to date_suggestions_path, alert: 'Unable to generate suggestions. Please try again.'
    end
  rescue StandardError => e
    Rails.logger.error("Error generating suggestions: #{e.message}")
    redirect_to date_suggestions_path, alert: "Error: #{e.message}"
  end

  def plan
    @date_suggestion = DateSuggestion.find(params[:id])
    
    return unless validate_future_date(params[:scheduled_for], date_suggestion_path(@date_suggestion))
    
    @planning_session = PlanningSession.new(
      date_suggestion: @date_suggestion,
      ip_address: request.remote_ip
    )
  end

  def new
  end

  private

  def planning_session_params
    params.require(:planning_session).permit(:scheduled_for, :email, :phone, :date_suggestion_id)
  end
  
  def validate_future_date(date_param, redirect_path)
    return true if date_param.blank?
    
    begin
      selected_date = Date.parse(date_param)
      if selected_date < Date.current
        redirect_to redirect_path, alert: "Please select a future date"
        return false
      end
      true
    rescue Date::Error
      redirect_to redirect_path, alert: "Invalid date format"
      false
    end
  end
end
