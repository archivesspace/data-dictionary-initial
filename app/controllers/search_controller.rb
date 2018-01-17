class SearchController < ApplicationController
  def show
    @fields = Field.like(params[:query])
  end
end
