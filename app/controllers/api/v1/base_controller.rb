module Api
  module V1
    class BaseController < ApplicationController
      include SchoolResolver
    end
  end
end
