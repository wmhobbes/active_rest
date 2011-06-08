class User < ActiveRecord::Base
  include ActiveRest::Model

  belongs_to :company
  has_many :contacts,:as => :owner
end
