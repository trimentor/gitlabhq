# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::DraftNotes, feature_category: :code_review_workflow do
  let_it_be(:user) { create(:user) }
  let_it_be(:user_2) { create(:user) }
  let_it_be(:project) { create(:project, :public) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project, target_project: project, author: user) }

  let_it_be(:merge_request_note) { create(:note, noteable: merge_request, project: project, author: user) }
  let_it_be(:draft_note_by_current_user) { create(:draft_note, merge_request: merge_request, author: user) }
  let_it_be(:draft_note_by_random_user) { create(:draft_note, merge_request: merge_request) }

  before do
    project.add_developer(user)
  end

  describe "Get a list of merge request draft notes" do
    it "returns 200 OK status" do
      get api("/projects/#{project.id}/merge_requests/#{merge_request.iid}/draft_notes", user)

      expect(response).to have_gitlab_http_status(:ok)
    end

    it "returns only draft notes authored by the current user" do
      get api("/projects/#{project.id}/merge_requests/#{merge_request.iid}/draft_notes", user)

      draft_note_ids = json_response.pluck("id")

      expect(draft_note_ids).to include(draft_note_by_current_user.id)
      expect(draft_note_ids).not_to include(draft_note_by_random_user.id)
      expect(draft_note_ids).not_to include(merge_request_note.id)
    end
  end

  describe "Get a single draft note" do
    context "when requesting an existing draft note by the user" do
      before do
        get api(
          "/projects/#{project.id}/merge_requests/#{merge_request.iid}/draft_notes/#{draft_note_by_current_user.id}",
          user
        )
      end

      it "returns 200 OK status" do
        expect(response).to have_gitlab_http_status(:ok)
      end

      it "returns the requested draft note" do
        expect(json_response["id"]).to eq(draft_note_by_current_user.id)
      end

      context "when requesting a non-existent draft note" do
        it "returns a 404 Not Found response" do
          get api(
            "/projects/#{project.id}/merge_requests/#{merge_request.iid}/draft_notes/#{DraftNote.last.id + 1}",
            user
          )

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context "when requesting an existing draft note by another user" do
        it "returns a 404 Not Found response" do
          get api(
            "/projects/#{project.id}/merge_requests/#{merge_request.iid}/draft_notes/#{draft_note_by_random_user.id}",
            user
          )

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end
    end
  end
end
