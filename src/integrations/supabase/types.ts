export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.18"
  }
  public: {
    Tables: {
      audit_log: {
        Row: {
          action: string
          actor: string | null
          created_at: string
          details: Json | null
          entity_id: string | null
          entity_type: string
          financial: boolean
          id: number
          reason: string | null
        }
        Insert: {
          action: string
          actor?: string | null
          created_at?: string
          details?: Json | null
          entity_id?: string | null
          entity_type: string
          financial?: boolean
          id?: number
          reason?: string | null
        }
        Update: {
          action?: string
          actor?: string | null
          created_at?: string
          details?: Json | null
          entity_id?: string | null
          entity_type?: string
          financial?: boolean
          id?: number
          reason?: string | null
        }
        Relationships: []
      }
      house_history: {
        Row: {
          changed_by: string | null
          created_at: string
          house_id: string
          id: string
          note: string | null
          snapshot: Json
        }
        Insert: {
          changed_by?: string | null
          created_at?: string
          house_id: string
          id?: string
          note?: string | null
          snapshot: Json
        }
        Update: {
          changed_by?: string | null
          created_at?: string
          house_id?: string
          id?: string
          note?: string | null
          snapshot?: Json
        }
        Relationships: [
          {
            foreignKeyName: "house_history_house_id_fkey"
            columns: ["house_id"]
            isOneToOne: false
            referencedRelation: "houses"
            referencedColumns: ["id"]
          },
        ]
      }
      house_requests: {
        Row: {
          address: string | null
          block: string | null
          created_at: string
          decided_by: string | null
          decision_reason: string | null
          house_number: string
          id: string
          occupancy: string
          relation: string
          status: string
          user_id: string
        }
        Insert: {
          address?: string | null
          block?: string | null
          created_at?: string
          decided_by?: string | null
          decision_reason?: string | null
          house_number: string
          id?: string
          occupancy?: string
          relation?: string
          status?: string
          user_id: string
        }
        Update: {
          address?: string | null
          block?: string | null
          created_at?: string
          decided_by?: string | null
          decision_reason?: string | null
          house_number?: string
          id?: string
          occupancy?: string
          relation?: string
          status?: string
          user_id?: string
        }
        Relationships: []
      }
      houses: {
        Row: {
          active: boolean
          address: string | null
          block: string | null
          created_at: string
          house_number: string
          id: string
          is_demo: boolean
          occupancy: string
          owner_mobile: string | null
          owner_name: string | null
          owner_since: string | null
          primary_admin: string | null
          tenant_mobile: string | null
          tenant_name: string | null
          tenant_since: string | null
        }
        Insert: {
          active?: boolean
          address?: string | null
          block?: string | null
          created_at?: string
          house_number: string
          id?: string
          is_demo?: boolean
          occupancy?: string
          owner_mobile?: string | null
          owner_name?: string | null
          owner_since?: string | null
          primary_admin?: string | null
          tenant_mobile?: string | null
          tenant_name?: string | null
          tenant_since?: string | null
        }
        Update: {
          active?: boolean
          address?: string | null
          block?: string | null
          created_at?: string
          house_number?: string
          id?: string
          is_demo?: boolean
          occupancy?: string
          owner_mobile?: string | null
          owner_name?: string | null
          owner_since?: string | null
          primary_admin?: string | null
          tenant_mobile?: string | null
          tenant_name?: string | null
          tenant_since?: string | null
        }
        Relationships: []
      }
      invitations: {
        Row: {
          created_at: string
          created_by: string
          expires_at: string
          house_id: string
          id: string
          revoked_at: string | null
          token: string
        }
        Insert: {
          created_at?: string
          created_by: string
          expires_at: string
          house_id: string
          id?: string
          revoked_at?: string | null
          token?: string
        }
        Update: {
          created_at?: string
          created_by?: string
          expires_at?: string
          house_id?: string
          id?: string
          revoked_at?: string | null
          token?: string
        }
        Relationships: [
          {
            foreignKeyName: "invitations_house_id_fkey"
            columns: ["house_id"]
            isOneToOne: false
            referencedRelation: "houses"
            referencedColumns: ["id"]
          },
        ]
      }
      manager_permissions: {
        Row: {
          created_at: string
          granted_by: string | null
          permission: string
          user_id: string
        }
        Insert: {
          created_at?: string
          granted_by?: string | null
          permission: string
          user_id: string
        }
        Update: {
          created_at?: string
          granted_by?: string | null
          permission?: string
          user_id?: string
        }
        Relationships: []
      }
      memberships: {
        Row: {
          created_at: string
          decided_by: string | null
          decision_reason: string | null
          ended_at: string | null
          house_id: string
          id: string
          invitation_id: string | null
          is_house_admin: boolean
          relation: string
          started_at: string | null
          status: string
          user_id: string
        }
        Insert: {
          created_at?: string
          decided_by?: string | null
          decision_reason?: string | null
          ended_at?: string | null
          house_id: string
          id?: string
          invitation_id?: string | null
          is_house_admin?: boolean
          relation?: string
          started_at?: string | null
          status?: string
          user_id: string
        }
        Update: {
          created_at?: string
          decided_by?: string | null
          decision_reason?: string | null
          ended_at?: string | null
          house_id?: string
          id?: string
          invitation_id?: string | null
          is_house_admin?: boolean
          relation?: string
          started_at?: string | null
          status?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "memberships_house_id_fkey"
            columns: ["house_id"]
            isOneToOne: false
            referencedRelation: "houses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "memberships_invitation_id_fkey"
            columns: ["invitation_id"]
            isOneToOne: false
            referencedRelation: "invitations"
            referencedColumns: ["id"]
          },
        ]
      }
      notifications: {
        Row: {
          body: string | null
          created_at: string
          dismissed_at: string | null
          id: string
          kind: string
          link: string | null
          read_at: string | null
          title: string
          user_id: string
        }
        Insert: {
          body?: string | null
          created_at?: string
          dismissed_at?: string | null
          id?: string
          kind: string
          link?: string | null
          read_at?: string | null
          title: string
          user_id: string
        }
        Update: {
          body?: string | null
          created_at?: string
          dismissed_at?: string | null
          id?: string
          kind?: string
          link?: string | null
          read_at?: string | null
          title?: string
          user_id?: string
        }
        Relationships: []
      }
      profiles: {
        Row: {
          created_at: string
          full_name: string
          id: string
          is_demo: boolean
          mobile: string
          must_change_password: boolean
          status: Database["public"]["Enums"]["account_status"]
          status_reason: string | null
        }
        Insert: {
          created_at?: string
          full_name?: string
          id: string
          is_demo?: boolean
          mobile: string
          must_change_password?: boolean
          status?: Database["public"]["Enums"]["account_status"]
          status_reason?: string | null
        }
        Update: {
          created_at?: string
          full_name?: string
          id?: string
          is_demo?: boolean
          mobile?: string
          must_change_password?: boolean
          status?: Database["public"]["Enums"]["account_status"]
          status_reason?: string | null
        }
        Relationships: []
      }
      society_settings: {
        Row: {
          address: string | null
          id: number
          invite_days: number
          show_demo: boolean
          society_name: string
          updated_at: string
        }
        Insert: {
          address?: string | null
          id?: number
          invite_days?: number
          show_demo?: boolean
          society_name?: string
          updated_at?: string
        }
        Update: {
          address?: string | null
          id?: number
          invite_days?: number
          show_demo?: boolean
          society_name?: string
          updated_at?: string
        }
        Relationships: []
      }
      user_roles: {
        Row: {
          id: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Insert: {
          id?: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Update: {
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          user_id?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      _audit: {
        Args: {
          _action: string
          _details: Json
          _eid: string
          _etype: string
          _fin?: boolean
          _reason: string
        }
        Returns: undefined
      }
      _notify: {
        Args: {
          _body: string
          _kind: string
          _link: string
          _title: string
          _uid: string
        }
        Returns: undefined
      }
      _notify_admins: {
        Args: { _body: string; _kind: string; _link: string; _title: string }
        Returns: undefined
      }
      _notify_all: {
        Args: { _body: string; _kind: string; _link: string; _title: string }
        Returns: undefined
      }
      _notify_perm: {
        Args: {
          _body: string
          _kind: string
          _link: string
          _perm: string
          _title: string
        }
        Returns: undefined
      }
      _require_active: { Args: never; Returns: undefined }
      _require_admin: { Args: never; Returns: undefined }
      _require_perm: { Args: { _perm: string }; Returns: undefined }
      accept_invitation: {
        Args: { _relation: string; _token: string }
        Returns: string
      }
      attach_provisioned_member: {
        Args: {
          _house: string
          _is_house_admin: boolean
          _relation: string
          _user: string
        }
        Returns: undefined
      }
      clear_must_change_password: { Args: never; Returns: undefined }
      create_house: {
        Args: {
          _address: string
          _block: string
          _number: string
          _occupancy: string
          _owner_mobile: string
          _owner_name: string
        }
        Returns: string
      }
      create_invitation: {
        Args: { _days: number; _house: string }
        Returns: string
      }
      decide_house_request: {
        Args: { _approve: boolean; _reason: string; _req: string }
        Returns: undefined
      }
      decide_membership: {
        Args: { _approve: boolean; _membership: string; _reason: string }
        Returns: undefined
      }
      end_membership: {
        Args: { _membership: string; _reason: string }
        Returns: undefined
      }
      has_perm: { Args: { _perm: string; _uid: string }; Returns: boolean }
      has_role: {
        Args: { _role: Database["public"]["Enums"]["app_role"]; _uid: string }
        Returns: boolean
      }
      invitation_info: { Args: { _token: string }; Returns: Json }
      is_active_member: { Args: { _uid: string }; Returns: boolean }
      is_admin: { Args: { _uid: string }; Returns: boolean }
      is_house_admin_of: {
        Args: { _house: string; _uid: string }
        Returns: boolean
      }
      log_password_reset: {
        Args: { _reason: string; _user: string }
        Returns: undefined
      }
      mark_notification: {
        Args: { _action: string; _id: string }
        Returns: undefined
      }
      my_house_id: { Args: { _uid: string }; Returns: string }
      normalize_mobile: { Args: { _m: string }; Returns: string }
      request_house_membership: {
        Args: { _house_number: string; _relation: string }
        Returns: string
      }
      request_new_house: {
        Args: {
          _address: string
          _block: string
          _house_number: string
          _occupancy: string
          _relation: string
        }
        Returns: string
      }
      revoke_invitation: { Args: { _inv: string }; Returns: undefined }
      set_account_status: {
        Args: {
          _reason: string
          _status: Database["public"]["Enums"]["account_status"]
          _user: string
        }
        Returns: undefined
      }
      set_house_admin: {
        Args: { _is_admin: boolean; _membership: string; _primary: boolean }
        Returns: undefined
      }
      set_manager_permissions: {
        Args: { _perms: string[]; _user: string }
        Returns: undefined
      }
      set_role: {
        Args: {
          _grant: boolean
          _role: Database["public"]["Enums"]["app_role"]
          _user: string
        }
        Returns: undefined
      }
      update_house: {
        Args: { _data: Json; _house: string; _note: string }
        Returns: undefined
      }
      update_my_profile: { Args: { _full_name: string }; Returns: undefined }
      update_settings: {
        Args: { _address: string; _invite_days: number; _name: string }
        Returns: undefined
      }
    }
    Enums: {
      account_status:
        | "pending_society"
        | "pending_household"
        | "active"
        | "rejected"
        | "suspended"
      app_role: "society_admin" | "society_manager"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      account_status: [
        "pending_society",
        "pending_household",
        "active",
        "rejected",
        "suspended",
      ],
      app_role: ["society_admin", "society_manager"],
    },
  },
} as const
