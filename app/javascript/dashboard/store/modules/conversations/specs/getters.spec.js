import { describe, it, expect } from 'vitest';
import getters from '../getters';

describe('Conversation Getters', () => {
  describe('#getUnAssignedChats', () => {
    const baseFilters = { status: 'all' };

    const unassignedConversation = {
      id: 1,
      status: 'open',
      inbox_id: 1,
      labels: [],
      meta: {},
    };

    const humanAssignedConversation = {
      id: 2,
      status: 'open',
      inbox_id: 1,
      labels: [],
      meta: { assignee: { id: 10 }, assignee_type: 'User' },
    };

    const botAssignedConversation = {
      id: 3,
      status: 'open',
      inbox_id: 1,
      labels: [],
      meta: { assignee: { id: 20 }, assignee_type: 'AgentBot' },
    };

    it('includes conversations with no assignee at all', () => {
      const state = { allConversations: [unassignedConversation] };
      const result = getters.getUnAssignedChats(state)(baseFilters);
      expect(result).toEqual([unassignedConversation]);
    });

    it('excludes conversations assigned to a human agent', () => {
      const state = { allConversations: [humanAssignedConversation] };
      const result = getters.getUnAssignedChats(state)(baseFilters);
      expect(result).toEqual([]);
    });

    // Regression test: Chatwoot v4.16.2 started auto-assigning conversations
    // in bot-active inboxes to the AgentBot (assignee_agent_bot), which
    // populates meta.assignee just like a human assignment would. Without
    // this check, these conversations vanish from the "Unassigned" list even
    // though the backend's own `unassigned` scope (assignee_id: nil) still
    // counts them — that mismatch drove ChatList.vue's pagination into an
    // infinite refetch loop.
    it('still includes conversations auto-assigned to an AgentBot', () => {
      const state = { allConversations: [botAssignedConversation] };
      const result = getters.getUnAssignedChats(state)(baseFilters);
      expect(result).toEqual([botAssignedConversation]);
    });

    it('correctly partitions a mixed list', () => {
      const state = {
        allConversations: [
          unassignedConversation,
          humanAssignedConversation,
          botAssignedConversation,
        ],
      };
      const result = getters.getUnAssignedChats(state)(baseFilters);
      expect(result).toEqual([unassignedConversation, botAssignedConversation]);
    });
  });
});
