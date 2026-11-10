
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  
  "graphql_public": {
          Tables: {
            [_ in never]: never
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            "graphql":
{ Args: { "extensions"?: Json,"operationName"?: string,"query"?: string,"variables"?: Json }; Returns: Json
                           }
          }
          Enums: {
            [_ in never]: never
          }
          CompositeTypes: {
            [_ in never]: never
          }
        },"public": {
          Tables: {
            "agreement_documents": {
                  Row: {
                    "agreement_id": string,"document_name": string,"document_type": Database["public"]['Enums']["agreement_document_type"],"file_r2_key": string | null,"id": string,"updated_at": string,"uploaded_at": string,"uploaded_by": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "agreement_id": string,"document_name": string,"document_type": Database["public"]['Enums']["agreement_document_type"],"file_r2_key"?: string | null,"id"?: string,"updated_at"?: string,"uploaded_at"?: string,"uploaded_by"?: string | null
                  }
                  Update: {
                    "agreement_id"?: string,"document_name"?: string,"document_type"?: Database["public"]['Enums']["agreement_document_type"],"file_r2_key"?: string | null,"id"?: string,"updated_at"?: string,"uploaded_at"?: string,"uploaded_by"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "agreement_documents_agreement_id_fkey"
      columns: ["agreement_id"]
isOneToOne: false
      referencedRelation: "agreements_convenios"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "agreement_documents_agreement_id_fkey"
      columns: ["agreement_id"]
isOneToOne: false
      referencedRelation: "v_agreements"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "agreement_documents_uploaded_by_fkey"
      columns: ["uploaded_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"agreements_convenios": {
                  Row: {
                    "approved_at": string | null,"approved_by": string | null,"cancel_reason": string | null,"cancelled_at": string | null,"cancelled_by": string | null,"company_id": string,"created_at": string,"created_by": string | null,"deal_id": string | null,"documents_verified": boolean,"documents_verified_at": string | null,"documents_verified_by": string | null,"hr_approval_required": boolean,"id": string,"max_installments": number,"payroll_conditions": string | null,"payroll_frequency": Database["public"]['Enums']["payroll_frequency"],"status": Database["public"]['Enums']["agreement_status"],"updated_at": string,"valid_from": string | null,"valid_until": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "approved_at"?: string | null,"approved_by"?: string | null,"cancel_reason"?: string | null,"cancelled_at"?: string | null,"cancelled_by"?: string | null,"company_id": string,"created_at"?: string,"created_by"?: string | null,"deal_id"?: string | null,"documents_verified"?: boolean,"documents_verified_at"?: string | null,"documents_verified_by"?: string | null,"hr_approval_required"?: boolean,"id"?: string,"max_installments": number,"payroll_conditions"?: string | null,"payroll_frequency": Database["public"]['Enums']["payroll_frequency"],"status"?: Database["public"]['Enums']["agreement_status"],"updated_at"?: string,"valid_from"?: string | null,"valid_until"?: string | null
                  }
                  Update: {
                    "approved_at"?: string | null,"approved_by"?: string | null,"cancel_reason"?: string | null,"cancelled_at"?: string | null,"cancelled_by"?: string | null,"company_id"?: string,"created_at"?: string,"created_by"?: string | null,"deal_id"?: string | null,"documents_verified"?: boolean,"documents_verified_at"?: string | null,"documents_verified_by"?: string | null,"hr_approval_required"?: boolean,"id"?: string,"max_installments"?: number,"payroll_conditions"?: string | null,"payroll_frequency"?: Database["public"]['Enums']["payroll_frequency"],"status"?: Database["public"]['Enums']["agreement_status"],"updated_at"?: string,"valid_from"?: string | null,"valid_until"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "agreements_convenios_approved_by_fkey"
      columns: ["approved_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "agreements_convenios_cancelled_by_fkey"
      columns: ["cancelled_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "agreements_convenios_company_id_fkey"
      columns: ["company_id"]
isOneToOne: false
      referencedRelation: "companies"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "agreements_convenios_created_by_fkey"
      columns: ["created_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "agreements_convenios_documents_verified_by_fkey"
      columns: ["documents_verified_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "agreements_deal_same_company"
      columns: ["deal_id","company_id"]
isOneToOne: false
      referencedRelation: "deals_opportunities"
      referencedColumns: ["id","company_id"]
    },{
      foreignKeyName: "agreements_deal_same_company"
      columns: ["deal_id","company_id"]
isOneToOne: false
      referencedRelation: "v_deals_board"
      referencedColumns: ["id","company_id"]
    }
                  ]
                },"audit_logs": {
                  Row: {
                    "action": string,"changed_at": string,"changed_by": string | null,"id": number,"new_data": Json | null,"old_data": Json | null,"record_id": string,"table_name": string
                  }
                  ComputedFields: never
                  Insert: {
                    "action": string,"changed_at"?: string,"changed_by"?: string | null,"id"?: never,"new_data"?: Json | null,"old_data"?: Json | null,"record_id": string,"table_name": string
                  }
                  Update: {
                    "action"?: string,"changed_at"?: string,"changed_by"?: string | null,"id"?: never,"new_data"?: Json | null,"old_data"?: Json | null,"record_id"?: string,"table_name"?: string
                  }
                  Relationships: [
                    
                  ]
                },"campaign_attendance": {
                  Row: {
                    "area": string | null,"campaign_id": string,"created_at": string,"document_id": string,"full_name": string,"id": string,"registered_by": string | null,"session_id": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "area"?: string | null,"campaign_id": string,"created_at"?: string,"document_id": string,"full_name": string,"id"?: string,"registered_by"?: string | null,"session_id": string,"updated_at"?: string
                  }
                  Update: {
                    "area"?: string | null,"campaign_id"?: string,"created_at"?: string,"document_id"?: string,"full_name"?: string,"id"?: string,"registered_by"?: string | null,"session_id"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "campaign_attendance_campaign_id_fkey"
      columns: ["campaign_id"]
isOneToOne: false
      referencedRelation: "campaigns_jornadas"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "campaign_attendance_campaign_id_fkey"
      columns: ["campaign_id"]
isOneToOne: false
      referencedRelation: "v_campaigns"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "campaign_attendance_registered_by_fkey"
      columns: ["registered_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "campaign_attendance_session_same_campaign"
      columns: ["session_id","campaign_id"]
isOneToOne: false
      referencedRelation: "campaign_sessions"
      referencedColumns: ["id","campaign_id"]
    },{
      foreignKeyName: "campaign_attendance_session_same_campaign"
      columns: ["session_id","campaign_id"]
isOneToOne: false
      referencedRelation: "v_campaign_calendar"
      referencedColumns: ["session_id","campaign_id"]
    }
                  ]
                },"campaign_sessions": {
                  Row: {
                    "campaign_id": string,"created_at": string,"end_time": string,"id": string,"location_detail": string | null,"responsible_user_id": string,"session_date": string,"start_time": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "campaign_id": string,"created_at"?: string,"end_time": string,"id"?: string,"location_detail"?: string | null,"responsible_user_id": string,"session_date": string,"start_time": string,"updated_at"?: string
                  }
                  Update: {
                    "campaign_id"?: string,"created_at"?: string,"end_time"?: string,"id"?: string,"location_detail"?: string | null,"responsible_user_id"?: string,"session_date"?: string,"start_time"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "campaign_sessions_campaign_id_fkey"
      columns: ["campaign_id"]
isOneToOne: false
      referencedRelation: "campaigns_jornadas"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "campaign_sessions_campaign_id_fkey"
      columns: ["campaign_id"]
isOneToOne: false
      referencedRelation: "v_campaigns"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "campaign_sessions_responsible_user_id_fkey"
      columns: ["responsible_user_id"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"campaigns_jornadas": {
                  Row: {
                    "agreement_id": string,"branch_id": string | null,"cancel_reason": string | null,"cancelled_at": string | null,"city_id": string,"closed_at": string | null,"company_id": string,"created_at": string,"created_by": string | null,"deal_id": string,"id": string,"logistics_confirmed": boolean,"notes": string | null,"responsible_user_id": string,"started_at": string | null,"status": Database["public"]['Enums']["campaign_status"],"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "agreement_id": string,"branch_id"?: string | null,"cancel_reason"?: string | null,"cancelled_at"?: string | null,"city_id": string,"closed_at"?: string | null,"company_id": string,"created_at"?: string,"created_by"?: string | null,"deal_id": string,"id"?: string,"logistics_confirmed"?: boolean,"notes"?: string | null,"responsible_user_id": string,"started_at"?: string | null,"status"?: Database["public"]['Enums']["campaign_status"],"updated_at"?: string
                  }
                  Update: {
                    "agreement_id"?: string,"branch_id"?: string | null,"cancel_reason"?: string | null,"cancelled_at"?: string | null,"city_id"?: string,"closed_at"?: string | null,"company_id"?: string,"created_at"?: string,"created_by"?: string | null,"deal_id"?: string,"id"?: string,"logistics_confirmed"?: boolean,"notes"?: string | null,"responsible_user_id"?: string,"started_at"?: string | null,"status"?: Database["public"]['Enums']["campaign_status"],"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "campaigns_agreement_same_company"
      columns: ["agreement_id","company_id"]
isOneToOne: false
      referencedRelation: "agreements_convenios"
      referencedColumns: ["id","company_id"]
    },{
      foreignKeyName: "campaigns_agreement_same_company"
      columns: ["agreement_id","company_id"]
isOneToOne: false
      referencedRelation: "v_agreements"
      referencedColumns: ["id","company_id"]
    },{
      foreignKeyName: "campaigns_branch_same_company"
      columns: ["branch_id","company_id"]
isOneToOne: false
      referencedRelation: "company_branches"
      referencedColumns: ["id","company_id"]
    },{
      foreignKeyName: "campaigns_deal_same_company"
      columns: ["deal_id","company_id"]
isOneToOne: false
      referencedRelation: "deals_opportunities"
      referencedColumns: ["id","company_id"]
    },{
      foreignKeyName: "campaigns_deal_same_company"
      columns: ["deal_id","company_id"]
isOneToOne: false
      referencedRelation: "v_deals_board"
      referencedColumns: ["id","company_id"]
    },{
      foreignKeyName: "campaigns_jornadas_city_id_fkey"
      columns: ["city_id"]
isOneToOne: false
      referencedRelation: "cities"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "campaigns_jornadas_company_id_fkey"
      columns: ["company_id"]
isOneToOne: false
      referencedRelation: "companies"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "campaigns_jornadas_created_by_fkey"
      columns: ["created_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "campaigns_jornadas_responsible_user_id_fkey"
      columns: ["responsible_user_id"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"cities": {
                  Row: {
                    "active": boolean,"created_at": string,"id": string,"is_operational": boolean,"name": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"created_at"?: string,"id"?: string,"is_operational"?: boolean,"name": string,"updated_at"?: string
                  }
                  Update: {
                    "active"?: boolean,"created_at"?: string,"id"?: string,"is_operational"?: boolean,"name"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"companies": {
                  Row: {
                    "assigned_user_id": string | null,"created_at": string,"created_by": string | null,"id": string,"is_nit_provisional": boolean,"name": string,"name_normalized": string | null,"nit": string | null,"nit_dv": number | null,"nit_verified_at": string | null,"nit_verified_by": string | null,"payroll_frequency": Database["public"]['Enums']["payroll_frequency"] | null,"sector": string,"total_employees": number | null,"updated_at": string,"website": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "assigned_user_id"?: string | null,"created_at"?: string,"created_by"?: string | null,"id"?: string,"is_nit_provisional"?: boolean,"name": string,"name_normalized"?: never,"nit"?: string | null,"nit_dv"?: number | null,"nit_verified_at"?: string | null,"nit_verified_by"?: string | null,"payroll_frequency"?: Database["public"]['Enums']["payroll_frequency"] | null,"sector": string,"total_employees"?: number | null,"updated_at"?: string,"website"?: string | null
                  }
                  Update: {
                    "assigned_user_id"?: string | null,"created_at"?: string,"created_by"?: string | null,"id"?: string,"is_nit_provisional"?: boolean,"name"?: string,"name_normalized"?: never,"nit"?: string | null,"nit_dv"?: number | null,"nit_verified_at"?: string | null,"nit_verified_by"?: string | null,"payroll_frequency"?: Database["public"]['Enums']["payroll_frequency"] | null,"sector"?: string,"total_employees"?: number | null,"updated_at"?: string,"website"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "companies_assigned_user_id_fkey"
      columns: ["assigned_user_id"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "companies_created_by_fkey"
      columns: ["created_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "companies_nit_verified_by_fkey"
      columns: ["nit_verified_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"company_branches": {
                  Row: {
                    "address": string | null,"city_id": string | null,"city_other": string | null,"company_id": string,"created_at": string,"id": string,"is_main": boolean,"name": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "address"?: string | null,"city_id"?: string | null,"city_other"?: string | null,"company_id": string,"created_at"?: string,"id"?: string,"is_main"?: boolean,"name": string,"updated_at"?: string
                  }
                  Update: {
                    "address"?: string | null,"city_id"?: string | null,"city_other"?: string | null,"company_id"?: string,"created_at"?: string,"id"?: string,"is_main"?: boolean,"name"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "company_branches_city_id_fkey"
      columns: ["city_id"]
isOneToOne: false
      referencedRelation: "cities"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "company_branches_company_id_fkey"
      columns: ["company_id"]
isOneToOne: false
      referencedRelation: "companies"
      referencedColumns: ["id"]
    }
                  ]
                },"contacts": {
                  Row: {
                    "active": boolean,"area": Database["public"]['Enums']["contact_area"],"branch_id": string | null,"company_id": string,"created_at": string,"created_by": string | null,"email": string | null,"full_name": string,"id": string,"is_coordinator": boolean,"is_decision_maker": boolean,"phone_whatsapp": string | null,"role_title": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"area": Database["public"]['Enums']["contact_area"],"branch_id"?: string | null,"company_id": string,"created_at"?: string,"created_by"?: string | null,"email"?: string | null,"full_name": string,"id"?: string,"is_coordinator"?: boolean,"is_decision_maker"?: boolean,"phone_whatsapp"?: string | null,"role_title": string,"updated_at"?: string
                  }
                  Update: {
                    "active"?: boolean,"area"?: Database["public"]['Enums']["contact_area"],"branch_id"?: string | null,"company_id"?: string,"created_at"?: string,"created_by"?: string | null,"email"?: string | null,"full_name"?: string,"id"?: string,"is_coordinator"?: boolean,"is_decision_maker"?: boolean,"phone_whatsapp"?: string | null,"role_title"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "contacts_branch_same_company"
      columns: ["branch_id","company_id"]
isOneToOne: false
      referencedRelation: "company_branches"
      referencedColumns: ["id","company_id"]
    },{
      foreignKeyName: "contacts_company_id_fkey"
      columns: ["company_id"]
isOneToOne: false
      referencedRelation: "companies"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "contacts_created_by_fkey"
      columns: ["created_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"deal_interaction_logs": {
                  Row: {
                    "created_at": string,"deal_id": string,"id": string,"interaction_note": string,"interaction_type": Database["public"]['Enums']["interaction_type"],"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"deal_id": string,"id"?: string,"interaction_note": string,"interaction_type": Database["public"]['Enums']["interaction_type"],"user_id"?: string
                  }
                  Update: {
                    "created_at"?: string,"deal_id"?: string,"id"?: string,"interaction_note"?: string,"interaction_type"?: Database["public"]['Enums']["interaction_type"],"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "deal_interaction_logs_deal_id_fkey"
      columns: ["deal_id"]
isOneToOne: false
      referencedRelation: "deals_opportunities"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "deal_interaction_logs_deal_id_fkey"
      columns: ["deal_id"]
isOneToOne: false
      referencedRelation: "v_deals_board"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "deal_interaction_logs_user_id_fkey"
      columns: ["user_id"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"deal_origins": {
                  Row: {
                    "active": boolean,"code": string,"created_at": string,"label": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"code": string,"created_at"?: string,"label": string,"updated_at"?: string
                  }
                  Update: {
                    "active"?: boolean,"code"?: string,"created_at"?: string,"label"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"deals_opportunities": {
                  Row: {
                    "assigned_user_id": string,"average_ticket_t_snapshot": number,"branch_id": string | null,"city_id": string,"company_id": string,"conversion_rate_c_snapshot": number,"created_at": string,"created_by": string | null,"deal_name_branch": string,"estimated_billing_amount": number | null,"estimated_close_date": string | null,"id": string,"last_interaction_at": string | null,"last_interaction_note": string | null,"last_interaction_type": Database["public"]['Enums']["interaction_type"] | null,"lost_substatus": Database["public"]['Enums']["lost_substatus"] | null,"next_action": string | null,"next_action_due_date": string | null,"next_action_owner_id": string | null,"origin_code": string,"payroll_frequency": Database["public"]['Enums']["payroll_frequency"] | null,"primary_contact_id": string | null,"reached_agreement_at": string | null,"stage": Database["public"]['Enums']["deal_stage"],"target_employees_n": number | null,"tentative_campaign_date": string | null,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "assigned_user_id": string,"average_ticket_t_snapshot": number,"branch_id"?: string | null,"city_id": string,"company_id": string,"conversion_rate_c_snapshot": number,"created_at"?: string,"created_by"?: string | null,"deal_name_branch": string,"estimated_billing_amount"?: never,"estimated_close_date"?: string | null,"id"?: string,"last_interaction_at"?: string | null,"last_interaction_note"?: string | null,"last_interaction_type"?: Database["public"]['Enums']["interaction_type"] | null,"lost_substatus"?: Database["public"]['Enums']["lost_substatus"] | null,"next_action"?: string | null,"next_action_due_date"?: string | null,"next_action_owner_id"?: string | null,"origin_code": string,"payroll_frequency"?: Database["public"]['Enums']["payroll_frequency"] | null,"primary_contact_id"?: string | null,"reached_agreement_at"?: string | null,"stage"?: Database["public"]['Enums']["deal_stage"],"target_employees_n"?: number | null,"tentative_campaign_date"?: string | null,"updated_at"?: string
                  }
                  Update: {
                    "assigned_user_id"?: string,"average_ticket_t_snapshot"?: number,"branch_id"?: string | null,"city_id"?: string,"company_id"?: string,"conversion_rate_c_snapshot"?: number,"created_at"?: string,"created_by"?: string | null,"deal_name_branch"?: string,"estimated_billing_amount"?: never,"estimated_close_date"?: string | null,"id"?: string,"last_interaction_at"?: string | null,"last_interaction_note"?: string | null,"last_interaction_type"?: Database["public"]['Enums']["interaction_type"] | null,"lost_substatus"?: Database["public"]['Enums']["lost_substatus"] | null,"next_action"?: string | null,"next_action_due_date"?: string | null,"next_action_owner_id"?: string | null,"origin_code"?: string,"payroll_frequency"?: Database["public"]['Enums']["payroll_frequency"] | null,"primary_contact_id"?: string | null,"reached_agreement_at"?: string | null,"stage"?: Database["public"]['Enums']["deal_stage"],"target_employees_n"?: number | null,"tentative_campaign_date"?: string | null,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "deals_branch_same_company"
      columns: ["branch_id","company_id"]
isOneToOne: false
      referencedRelation: "company_branches"
      referencedColumns: ["id","company_id"]
    },{
      foreignKeyName: "deals_contact_same_company"
      columns: ["primary_contact_id","company_id"]
isOneToOne: false
      referencedRelation: "contacts"
      referencedColumns: ["id","company_id"]
    },{
      foreignKeyName: "deals_opportunities_assigned_user_id_fkey"
      columns: ["assigned_user_id"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "deals_opportunities_city_id_fkey"
      columns: ["city_id"]
isOneToOne: false
      referencedRelation: "cities"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "deals_opportunities_company_id_fkey"
      columns: ["company_id"]
isOneToOne: false
      referencedRelation: "companies"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "deals_opportunities_created_by_fkey"
      columns: ["created_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "deals_opportunities_next_action_owner_id_fkey"
      columns: ["next_action_owner_id"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "deals_opportunities_origin_code_fkey"
      columns: ["origin_code"]
isOneToOne: false
      referencedRelation: "deal_origins"
      referencedColumns: ["code"]
    }
                  ]
                },"lab_providers": {
                  Row: {
                    "active": boolean,"contact_info": string | null,"created_at": string,"id": string,"name": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"contact_info"?: string | null,"created_at"?: string,"id"?: string,"name": string,"updated_at"?: string
                  }
                  Update: {
                    "active"?: boolean,"contact_info"?: string | null,"created_at"?: string,"id"?: string,"name"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"system_settings": {
                  Row: {
                    "description": string,"key": string,"updated_at": string,"updated_by": string | null,"value": number
                  }
                  ComputedFields: never
                  Insert: {
                    "description": string,"key": string,"updated_at"?: string,"updated_by"?: string | null,"value": number
                  }
                  Update: {
                    "description"?: string,"key"?: string,"updated_at"?: string,"updated_by"?: string | null,"value"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "system_settings_updated_by_fkey"
      columns: ["updated_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"users_profiles": {
                  Row: {
                    "active": boolean,"created_at": string,"email": string,"full_name": string,"id": string,"lab_provider_id": string | null,"role": Database["public"]['Enums']["app_role"] | null,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"created_at"?: string,"email": string,"full_name": string,"id": string,"lab_provider_id"?: string | null,"role"?: Database["public"]['Enums']["app_role"] | null,"updated_at"?: string
                  }
                  Update: {
                    "active"?: boolean,"created_at"?: string,"email"?: string,"full_name"?: string,"id"?: string,"lab_provider_id"?: string | null,"role"?: Database["public"]['Enums']["app_role"] | null,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "users_profiles_lab_provider_id_fkey"
      columns: ["lab_provider_id"]
isOneToOne: false
      referencedRelation: "lab_providers"
      referencedColumns: ["id"]
    }
                  ]
                }
          }
          Views: {
            "v_agreements": {
                  Row: {
                    "approved_at": string | null,"approved_by": string | null,"cancel_reason": string | null,"cancelled_at": string | null,"company_id": string,"company_name": string,"created_at": string,"deal_id": string | null,"deal_name_branch": string | null,"documents_count": number | null,"documents_pending_file": number | null,"documents_verified": boolean,"documents_verified_at": string | null,"documents_verified_by": string | null,"effective_status": string | null,"has_signed_document": boolean | null,"hr_approval_required": boolean,"id": string,"max_installments": number,"payroll_conditions": string | null,"payroll_frequency": Database["public"]['Enums']["payroll_frequency"],"status": Database["public"]['Enums']["agreement_status"],"updated_at": string,"valid_from": string | null,"valid_until": string | null
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "agreements_convenios_approved_by_fkey"
      columns: ["approved_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "agreements_convenios_company_id_fkey"
      columns: ["company_id"]
isOneToOne: false
      referencedRelation: "companies"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "agreements_convenios_documents_verified_by_fkey"
      columns: ["documents_verified_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "agreements_deal_same_company"
      columns: ["deal_id","company_id"]
isOneToOne: false
      referencedRelation: "deals_opportunities"
      referencedColumns: ["id","company_id"]
    },{
      foreignKeyName: "agreements_deal_same_company"
      columns: ["deal_id","company_id"]
isOneToOne: false
      referencedRelation: "v_deals_board"
      referencedColumns: ["id","company_id"]
    }
                  ]
                },"v_campaign_calendar": {
                  Row: {
                    "branch_name": string | null,"campaign_id": string,"campaign_status": Database["public"]['Enums']["campaign_status"],"city_id": string,"city_name": string,"company_name": string,"deal_name_branch": string,"end_time": string,"has_conflict": boolean | null,"location_detail": string | null,"responsible_user_id": string,"responsible_user_name": string,"session_date": string,"session_id": string,"start_time": string
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "campaign_sessions_campaign_id_fkey"
      columns: ["campaign_id"]
isOneToOne: false
      referencedRelation: "campaigns_jornadas"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "campaign_sessions_campaign_id_fkey"
      columns: ["campaign_id"]
isOneToOne: false
      referencedRelation: "v_campaigns"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "campaign_sessions_responsible_user_id_fkey"
      columns: ["responsible_user_id"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "campaigns_jornadas_city_id_fkey"
      columns: ["city_id"]
isOneToOne: false
      referencedRelation: "cities"
      referencedColumns: ["id"]
    }
                  ]
                },"v_campaigns": {
                  Row: {
                    "agreement_id": string,"attended_headcount": number | null,"branch_id": string | null,"branch_name": string | null,"cancel_reason": string | null,"cancelled_at": string | null,"city_id": string,"city_name": string,"closed_at": string | null,"company_id": string,"company_name": string,"created_at": string,"deal_id": string,"deal_name_branch": string,"estimated_billing_amount": number | null,"first_session_date": string | null,"id": string,"last_session_date": string | null,"logistics_confirmed": boolean,"notes": string | null,"responsible_user_id": string,"responsible_user_name": string,"sessions_count": number | null,"started_at": string | null,"status": Database["public"]['Enums']["campaign_status"],"target_employees_n": number | null,"updated_at": string
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "campaigns_agreement_same_company"
      columns: ["agreement_id","company_id"]
isOneToOne: false
      referencedRelation: "agreements_convenios"
      referencedColumns: ["id","company_id"]
    },{
      foreignKeyName: "campaigns_agreement_same_company"
      columns: ["agreement_id","company_id"]
isOneToOne: false
      referencedRelation: "v_agreements"
      referencedColumns: ["id","company_id"]
    },{
      foreignKeyName: "campaigns_branch_same_company"
      columns: ["branch_id","company_id"]
isOneToOne: false
      referencedRelation: "company_branches"
      referencedColumns: ["id","company_id"]
    },{
      foreignKeyName: "campaigns_deal_same_company"
      columns: ["deal_id","company_id"]
isOneToOne: false
      referencedRelation: "deals_opportunities"
      referencedColumns: ["id","company_id"]
    },{
      foreignKeyName: "campaigns_deal_same_company"
      columns: ["deal_id","company_id"]
isOneToOne: false
      referencedRelation: "v_deals_board"
      referencedColumns: ["id","company_id"]
    },{
      foreignKeyName: "campaigns_jornadas_city_id_fkey"
      columns: ["city_id"]
isOneToOne: false
      referencedRelation: "cities"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "campaigns_jornadas_company_id_fkey"
      columns: ["company_id"]
isOneToOne: false
      referencedRelation: "companies"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "campaigns_jornadas_responsible_user_id_fkey"
      columns: ["responsible_user_id"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"v_deals_board": {
                  Row: {
                    "assigned_user_id": string,"assigned_user_name": string,"branch_id": string | null,"city_id": string,"city_name": string,"company_id": string,"company_name": string,"created_at": string,"days_inactive": number | null,"deal_name_branch": string,"estimated_billing_amount": number | null,"estimated_close_date": string | null,"id": string,"inactivity_alert": boolean | null,"is_new_business": boolean | null,"last_interaction_at": string | null,"last_interaction_note": string | null,"last_interaction_type": Database["public"]['Enums']["interaction_type"] | null,"lost_substatus": Database["public"]['Enums']["lost_substatus"] | null,"next_action": string | null,"next_action_due_date": string | null,"next_action_overdue": boolean | null,"next_action_owner_id": string | null,"origin_code": string,"stage": Database["public"]['Enums']["deal_stage"],"target_employees_n": number | null,"tentative_campaign_date": string | null,"updated_at": string
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "deals_branch_same_company"
      columns: ["branch_id","company_id"]
isOneToOne: false
      referencedRelation: "company_branches"
      referencedColumns: ["id","company_id"]
    },{
      foreignKeyName: "deals_opportunities_assigned_user_id_fkey"
      columns: ["assigned_user_id"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "deals_opportunities_city_id_fkey"
      columns: ["city_id"]
isOneToOne: false
      referencedRelation: "cities"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "deals_opportunities_company_id_fkey"
      columns: ["company_id"]
isOneToOne: false
      referencedRelation: "companies"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "deals_opportunities_next_action_owner_id_fkey"
      columns: ["next_action_owner_id"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "deals_opportunities_origin_code_fkey"
      columns: ["origin_code"]
isOneToOne: false
      referencedRelation: "deal_origins"
      referencedColumns: ["code"]
    }
                  ]
                }
          }
          Functions: {
            "find_company_duplicates":
{ Args: { "p_name": string,"p_nit"?: string }; Returns: {
              "id": string,"is_nit_provisional": boolean,"match_reason": string,"name": string,"nit": string,"similarity": number
            }[]
                           },
"recalculate_deal_forecast":
{ Args: { "p_deal_id": string }; Returns: number
                           }
          }
          Enums: {
            "agreement_document_type": "convenio_firmado"|"camara_comercio"|"rut"|"formato_rrhh"|"otro","agreement_status": "borrador"|"pendiente_aprobacion"|"aprobado"|"cancelado","app_role": "comercial"|"operacion"|"administracion_cartera"|"direccion"|"proveedor_lab","campaign_status": "programada"|"en_ejecucion"|"cerrada"|"cancelada","contact_area": "rrhh"|"sst"|"gerencia"|"compras"|"otra","deal_stage": "prospecto"|"reunion_exploratoria"|"propuesta_enviada"|"negociacion"|"convenio_firmado"|"jornada_en_ejecucion"|"facturacion_cerrada"|"cierre_perdido","interaction_type": "reunion"|"llamada"|"whatsapp"|"correo","lost_substatus": "nurturing"|"no_contactar","payroll_frequency": "mensual"|"quincenal"
          }
          CompositeTypes: {
            [_ in never]: never
          }
        }
}

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
  ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
      Row: infer R
    }
    ? R
    : never
  : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
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
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
  ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
  : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
  ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
  : never

export const Constants = {
  "graphql_public": {
          Enums: {
            
          }
        },"public": {
          Enums: {
            "agreement_document_type": ["convenio_firmado", "camara_comercio", "rut", "formato_rrhh", "otro"],"agreement_status": ["borrador", "pendiente_aprobacion", "aprobado", "cancelado"],"app_role": ["comercial", "operacion", "administracion_cartera", "direccion", "proveedor_lab"],"campaign_status": ["programada", "en_ejecucion", "cerrada", "cancelada"],"contact_area": ["rrhh", "sst", "gerencia", "compras", "otra"],"deal_stage": ["prospecto", "reunion_exploratoria", "propuesta_enviada", "negociacion", "convenio_firmado", "jornada_en_ejecucion", "facturacion_cerrada", "cierre_perdido"],"interaction_type": ["reunion", "llamada", "whatsapp", "correo"],"lost_substatus": ["nurturing", "no_contactar"],"payroll_frequency": ["mensual", "quincenal"]
          }
        }
} as const
