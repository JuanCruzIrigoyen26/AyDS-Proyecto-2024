require 'sinatra/base'
require 'bundler/setup'
require 'logger'
require 'sinatra/activerecord'

require 'sinatra/reloader' if Sinatra::Base.environment == :development

require_relative 'models/account'
require_relative 'models/answer'
require_relative 'models/test'
require_relative 'models/trivia'
require_relative 'models/game'
require_relative 'models/question'
require_relative 'models/account_trivia'
require_relative 'models/account_test'
require_relative 'models/account_game'
require_relative 'models/account_answer'

class App < Sinatra::Application
  def initialize(app = nil)
    super()
  end

  configure :production, :development do
    enable :logging

    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG if development?
    set :logger, logger
  end

  enable :sessions
  set :session_secret, 'super secret'

  set :views, File.join(File.dirname(__FILE__), 'views')
  set :public_folder, File.join(File.dirname(__FILE__), 'styles')

  configure :development do
    register Sinatra::Reloader
    after_reload do
      puts 'Reloaded...'
    end
  end

  before do
    @current_user = session[:account_id] && Account.find_by(id: session[:account_id])
  end

  helpers do
    def logged_in?
      !!@current_user
    end
  end

  GAME_URL_MAPPING = {
  'Counter Strike 2' => 'csgo',

  }


  get '/login' do
    error_message = params[:error]
    erb :login, locals: { error_message: error_message }
  end

  get '/' do
    if logged_in?
      redirect '/home'
    else
      redirect '/login'
    end
  end

  get '/perfil' do
    erb :perfil
  end

  get '/signup' do
    erb :signup
  end

  get '/home' do
    if session[:logged_in]
      @games = Game.all
      erb :home
    else
      redirect '/login'
    end
  end
  

  post '/login' do
    nickname = params[:nickname]
    password = params[:password]
    account = Account.find_by(nickname: nickname, password: password)

    if account
      session[:email] = account.email
      session[:account_id] = account.id
      session[:logged_in] = true
      redirect '/home'
    else
      redirect '/login?error=Invalid-username-or-password'
    end
  end

  post '/signup' do
    email = params[:email]
    password = params[:password]
    name = params[:name]
    nickname = params[:nickname]

    if Account.exists?(email: email)
      redirect '/signup?error=Email-already-exists'
    end

    if Account.exists?(nickname: nickname)
      redirect '/signup?error=Nickname-already-exists'
    end

    account = Account.new(email: email, password: password, name: name, nickname: nickname, progress: 0)

    if account.save
      session[:logged_in] = true
      session[:account_id] = account.id
      redirect '/login'
    else
      puts "Error al guardar la cuenta: #{account.errors.full_messages.join(", ")}"
      erb :signup, locals: { error_message: "Error al crear cuenta" }
    end
  end

  post '/home' do
    if session[:logged_in]
      selected_game_name = params[:game]
      account_id = session[:account_id]
  
      unless account_id
        status 400
        body "Account ID is missing in session."
        return
      end
  
      selected_game = Game.find_by(name: selected_game_name)
  
      if selected_game.nil?
        status 400
        body "Game not found."
        return
      end
  
      session[:selected_game] = selected_game.name
  
      if Account.exists?(id: account_id)
        account_game = AccountGame.find_or_create_by(account_id: account_id, game: selected_game)
        if account_game.save
          game_url_name = GAME_URL_MAPPING[selected_game.name] || selected_game.name
          redirect "/difficult/#{game_url_name}"
        else
          status 400
          body "Unable to save AccountGame."
        end
      else
        status 400
        body "Account ID does not exist."
      end
    else
      redirect "/login"
    end
  end

  post '/perfil' do
    if session[:logged_in]
      account_id = session[:account_id]
      new_username = params[:nickname]
      new_password = params[:password]
  
      account = Account.find(account_id)
  
      if account
        if new_username && !new_username.strip.empty?
          account.update(nickname: new_username) 
        end
  
        if new_password && !new_password.strip.empty?
          account.update(password: new_password) 
        end
  
        if account.save
          redirect '/perfil?success=true'
        else
          redirect '/perfil?error=update_failed'
        end
      else
        redirect '/perfil?error=account_not_found'
      end
    else
      redirect '/home'
    end
  end
  
  get '/final_exam/:test_letter/:question_number' do
    if session[:logged_in]
      account_id = session[:account_id]
  
      completed_trivia_count = AccountTrivia.where(account_id: account_id, trivias_completed: true).count
        
      if completed_trivia_count >= 3
        test_letter = params[:test_letter]
        question_number = params[:question_number].to_i
        @question = Question.find_by(number: question_number, test_letter: test_letter)
  
        if @question
          @answers = Answer.where(question_number: @question.number, test_letter: test_letter).shuffle
          @difficulty = test_letter
  
          erb :final_exam, locals: { question: @question, answers: @answers, difficulty: @difficulty }
        else
          redirect "/difficult/#{URI.encode(session[:selected_game])}" 
        end
      else
        redirect "/difficult/#{URI.encode(session[:selected_game])}?error=complete_all_trivias"  
      end
    else
      redirect '/home'
    end
  end
  

  post '/start_final_exam' do
    if session[:logged_in]
      account_id = session[:account_id]
      test_letter = params[:test_letter] || 'F'
      
      # Check if there is an error message
      error_message = 'Debe completar todas las trivias antes de acceder al examen final.' if params[:error] == 'complete_all_trivias'
  
      @test = Test.find_by(letter: test_letter)
  
      if @test
        account_test = AccountTest.find_or_initialize_by(account_id: account_id, test: @test)
        account_test.update(correct_answers: 0, test_completed: false)
        
        redirect "/final_exam/#{test_letter}/1"
      else
        redirect '/home'
      end
    else
      redirect '/home'
    end
  end
  
  
  
  post '/submit_final_exam_answer' do
    if session[:logged_in]
      account_id = session[:account_id]
      question_number = params[:question_number].to_i
      test_letter = params[:test_letter]
      selected_option = params[:selected_option]
  
      @question = Question.find_by(number: question_number, test_letter: test_letter)
      @test = Test.find_by(letter: test_letter)
      account_test = AccountTest.find_or_initialize_by(account_id: account_id, test: @test)
  
      if @question
        if selected_option
          selected_answer = Answer.find_by(number: selected_option, question_number: question_number, test_letter: test_letter)
  
          if selected_answer
            correct = selected_answer.correct
  
            account_answer = AccountAnswer.find_or_initialize_by(account_id: account_id, question_id: @question.id)
            account_answer.update(answer_id: selected_answer.id, correct: correct)
          
            if correct
              account_test.increment(:correct_answers)
            end
            account_test.save
  
            next_question_number = question_number + 1
            next_question = Question.find_by(number: next_question_number, test_letter: test_letter)
  
            if next_question
              redirect "/final_exam/#{test_letter}/#{next_question_number}"
            else
              account_test.update(test_completed: true)
  
              total_questions = Question.where(test_letter: test_letter).count
              correct_answers_count = account_test.correct_answers
              correct_answers_percentage = (correct_answers_count.to_f / total_questions * 100).round(2)
  
              erb :result_exam, locals: { correct_answers_percentage: correct_answers_percentage, correct_answers_count: correct_answers_count, total_questions: total_questions }
            end
          else
            redirect "/final_exam/#{test_letter}/#{question_number}?error=invalid_option"
          end
        else
          @answers = Answer.where(question_number: @question.number, test_letter: test_letter).shuffle
          @difficulty = test_letter
  
          erb :final_exam, locals: { question: @question, answers: @answers, difficulty: @difficulty, error: 'Debes seleccionar una opción antes de continuar.' }
        end
      else
        redirect "/difficult/#{session[:selected_game]}"
      end
    else
      redirect '/home'
    end
  end
  
    
  

  get '/difficult/:game' do
    if session[:logged_in]
      # Determine the selected game and check conditions
      selected_game = params[:game]
      @completed_trivias = AccountTrivia.where(account_id: session[:account_id], trivias_completed: true).count
      
      # Check if there is an error message to display
      error_message = nil
      if params[:error] == 'complete_all_trivias'
        error_message = 'Debe completar todas las trivias antes de acceder al examen final.'
      end
  
      erb :difficult, locals: { selected_game: selected_game, completed_trivias: @completed_trivias, error_message: error_message }
    else
      redirect '/home'
    end
  end
  

  get '/:game/:test_letter/:question_number' do
    if logged_in?
      test_letter = params[:test_letter]
      question_number = params[:question_number].to_i

      @question = Question.find_by(number: question_number, test_letter: test_letter)

      if @question
        @answers = Answer.where(question_number: @question.number, test_letter: test_letter).shuffle
        @difficulty = params[:test_letter] 

        erb :trivia, locals: { question: @question, answers: @answers, difficulty: @difficulty }
      else
        redirect "/difficult/#{session[:selected_game]}"
      end
    else
      redirect "/login"
    end
  end

  post '/submit_trivia_answer' do
    if session[:logged_in]
      account_id = session[:account_id]
      question_number = params[:question_number].to_i
      test_letter = params[:test_letter]
      selected_option = params[:selected_option]
  
      @question = Question.find_by(number: question_number, test_letter: test_letter)
      @test = Test.find_by(letter: test_letter)
  
      if @question
        if selected_option
          selected_answer = Answer.find_by(number: selected_option, question_number: question_number, test_letter: test_letter)
  
          if selected_answer
            correct = selected_answer.correct
  
            account_answer = AccountAnswer.find_or_initialize_by(account_id: account_id, question_id: @question.id)
            account_answer.update(answer_id: selected_answer.id, correct: correct)

            trivia = Trivia.find_by(number: question_number, test_letter: test_letter)
  
            next_question_number = question_number + 1
            if question_number == 5
              account_trivia = AccountTrivia.find_or_create_by(account_id: account_id, trivias_id: trivia.id, trivias_completed: true)
  
              erb :result, locals: {
                correct: correct,
                description: trivia.description,
                question_number: question_number,
                test_letter: test_letter,
                trivia_completed: true,
                exam_final: false
              }
            else
              erb :result, locals: {
                correct: correct,
                description: trivia.description,
                question_number: question_number,
                test_letter: test_letter,
                trivia_completed: false,
                exam_final: false
              }
            end
          else
            @answers = Answer.where(question_number: @question.number, test_letter: test_letter).shuffle
            @difficulty = test_letter
  
            erb :trivia, locals: {
              question: @question,
              answers: @answers,
              difficulty: @difficulty,
              error: 'La opción seleccionada no es válida. Por favor, selecciona otra opción.'
            }
          end
        else
          @answers = Answer.where(question_number: @question.number, test_letter: test_letter).shuffle
          @difficulty = test_letter
  
          erb :trivia, locals: {
            question: @question,
            answers: @answers,
            difficulty: @difficulty,
            error: 'Debes seleccionar una opción antes de continuar.'
          }
        end
      else
        redirect "/difficult/#{session[:selected_game]}"
      end
    else
      redirect "/home"
    end
  end
    
  get '/result_exam' do
    if session[:logged_in]
      account_id = session[:account_id]
      test_letter = params[:test_letter]
  
      @test = Test.find_by(letter: test_letter)
      correct_answers = AccountTest.find_by(account_id: account_id, test_id: @test.id)
  
      if correct_answers
        total_questions = 5
        correct_answers_count = correct_answers.correct_answers 
        correct_answers_percentage = (correct_answers_count.to_f / total_questions * 100).round(2)

        erb :result_exam, locals: { correct_answers_percentage: correct_answers_percentage }

      else
        redirect "/difficult/#{session[:selected_game]}"
      end
    else
      redirect '/home'
    end
  end
  

  get '/logout' do
    session.clear
    redirect '/'
  end

  post '/logout' do
    session.clear
    redirect '/'
  end
end