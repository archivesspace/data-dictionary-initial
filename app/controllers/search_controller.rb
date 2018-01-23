class SearchController < ApplicationController
  def show
    if params[:query].present?
      @fields = Field.search_by_keyword(params[:query])
    else
     @fields = Field.all
    end
  end
end
