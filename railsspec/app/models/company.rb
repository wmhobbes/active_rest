class Company < ActiveRecord::Base
  has_many :users
  has_many :contacts,:as => :owner

  validates_presence_of :name
  validates_uniqueness_of :name
end
