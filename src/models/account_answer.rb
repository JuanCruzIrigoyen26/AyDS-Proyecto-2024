class AccountAnswer < ActiveRecord::Base
  self.table_name = 'account_answers'
    belongs_to :account
    belongs_to :question
    belongs_to :answer
  
    after_commit :update_progress_account
  
    private
  
    def update_progress_account
      account.update_progress
    end
  end