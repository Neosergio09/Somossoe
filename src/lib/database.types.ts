
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
                },"alegra_invoice_orders": {
                  Row: {
                    "amount_assigned": number,"created_at": string,"created_by": string | null,"id": string,"invoice_id": string,"order_id": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "amount_assigned": number,"created_at"?: string,"created_by"?: string | null,"id"?: string,"invoice_id": string,"order_id": string,"updated_at"?: string
                  }
                  Update: {
                    "amount_assigned"?: number,"created_at"?: string,"created_by"?: string | null,"id"?: string,"invoice_id"?: string,"order_id"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "alegra_invoice_orders_created_by_fkey"
      columns: ["created_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "alegra_invoice_orders_invoice_id_fkey"
      columns: ["invoice_id"]
isOneToOne: false
      referencedRelation: "alegra_invoices"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "alegra_invoice_orders_invoice_id_fkey"
      columns: ["invoice_id"]
isOneToOne: false
      referencedRelation: "v_invoices"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "alegra_invoice_orders_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "alegra_invoice_orders_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_order_margins"
      referencedColumns: ["order_id"]
    },{
      foreignKeyName: "alegra_invoice_orders_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "alegra_invoice_orders_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders_to_invoice"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "alegra_invoice_orders_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_receivables"
      referencedColumns: ["id"]
    }
                  ]
                },"alegra_invoices": {
                  Row: {
                    "alegra_external_id": string | null,"alegra_invoice_number": string,"alegra_status": string | null,"alegra_sync_error": string | null,"alegra_synced_at": string | null,"alegra_total": number | null,"buyer_id": string | null,"company_id": string | null,"created_at": string,"id": string,"invoice_date": string,"invoiced_amount": number,"is_voided": boolean,"notes": string | null,"radication_status": Database["public"]['Enums']["invoice_radication_status"],"registered_by": string | null,"updated_at": string,"void_reason": string | null,"voided_at": string | null,"voided_by": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "alegra_external_id"?: string | null,"alegra_invoice_number": string,"alegra_status"?: string | null,"alegra_sync_error"?: string | null,"alegra_synced_at"?: string | null,"alegra_total"?: number | null,"buyer_id"?: string | null,"company_id"?: string | null,"created_at"?: string,"id"?: string,"invoice_date": string,"invoiced_amount": number,"is_voided"?: boolean,"notes"?: string | null,"radication_status"?: Database["public"]['Enums']["invoice_radication_status"],"registered_by"?: string | null,"updated_at"?: string,"void_reason"?: string | null,"voided_at"?: string | null,"voided_by"?: string | null
                  }
                  Update: {
                    "alegra_external_id"?: string | null,"alegra_invoice_number"?: string,"alegra_status"?: string | null,"alegra_sync_error"?: string | null,"alegra_synced_at"?: string | null,"alegra_total"?: number | null,"buyer_id"?: string | null,"company_id"?: string | null,"created_at"?: string,"id"?: string,"invoice_date"?: string,"invoiced_amount"?: number,"is_voided"?: boolean,"notes"?: string | null,"radication_status"?: Database["public"]['Enums']["invoice_radication_status"],"registered_by"?: string | null,"updated_at"?: string,"void_reason"?: string | null,"voided_at"?: string | null,"voided_by"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "alegra_invoices_buyer_id_fkey"
      columns: ["buyer_id"]
isOneToOne: false
      referencedRelation: "buyers"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "alegra_invoices_company_id_fkey"
      columns: ["company_id"]
isOneToOne: false
      referencedRelation: "companies"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "alegra_invoices_registered_by_fkey"
      columns: ["registered_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "alegra_invoices_voided_by_fkey"
      columns: ["voided_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"alegra_sync_events": {
                  Row: {
                    "alegra_status": string | null,"alegra_total": number | null,"created_at": string,"id": number,"invoice_id": string,"message": string | null,"ok": boolean,"requested_by": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "alegra_status"?: string | null,"alegra_total"?: number | null,"created_at"?: string,"id"?: never,"invoice_id": string,"message"?: string | null,"ok": boolean,"requested_by"?: string | null
                  }
                  Update: {
                    "alegra_status"?: string | null,"alegra_total"?: number | null,"created_at"?: string,"id"?: never,"invoice_id"?: string,"message"?: string | null,"ok"?: boolean,"requested_by"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "alegra_sync_events_invoice_id_fkey"
      columns: ["invoice_id"]
isOneToOne: false
      referencedRelation: "alegra_invoices"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "alegra_sync_events_invoice_id_fkey"
      columns: ["invoice_id"]
isOneToOne: false
      referencedRelation: "v_invoices"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "alegra_sync_events_requested_by_fkey"
      columns: ["requested_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
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
                },"buyers": {
                  Row: {
                    "created_at": string,"created_by": string | null,"current_company_id": string | null,"data_consent_at": string | null,"data_consent_by": string | null,"data_consent_r2_key": string | null,"document_id": string,"document_type": Database["public"]['Enums']["buyer_document_type"],"email": string | null,"full_name": string,"id": string,"phone": string | null,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"created_by"?: string | null,"current_company_id"?: string | null,"data_consent_at"?: string | null,"data_consent_by"?: string | null,"data_consent_r2_key"?: string | null,"document_id": string,"document_type": Database["public"]['Enums']["buyer_document_type"],"email"?: string | null,"full_name": string,"id"?: string,"phone"?: string | null,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"created_by"?: string | null,"current_company_id"?: string | null,"data_consent_at"?: string | null,"data_consent_by"?: string | null,"data_consent_r2_key"?: string | null,"document_id"?: string,"document_type"?: Database["public"]['Enums']["buyer_document_type"],"email"?: string | null,"full_name"?: string,"id"?: string,"phone"?: string | null,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "buyers_created_by_fkey"
      columns: ["created_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "buyers_current_company_id_fkey"
      columns: ["current_company_id"]
isOneToOne: false
      referencedRelation: "companies"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "buyers_data_consent_by_fkey"
      columns: ["data_consent_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"campaign_attendance": {
                  Row: {
                    "area": string | null,"attended_at": string | null,"buyer_id": string | null,"campaign_id": string,"created_at": string,"document_id": string,"full_name": string,"id": string,"registered_by": string | null,"session_id": string,"status": Database["public"]['Enums']["attendance_status"],"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "area"?: string | null,"attended_at"?: string | null,"buyer_id"?: string | null,"campaign_id": string,"created_at"?: string,"document_id": string,"full_name": string,"id"?: string,"registered_by"?: string | null,"session_id": string,"status"?: Database["public"]['Enums']["attendance_status"],"updated_at"?: string
                  }
                  Update: {
                    "area"?: string | null,"attended_at"?: string | null,"buyer_id"?: string | null,"campaign_id"?: string,"created_at"?: string,"document_id"?: string,"full_name"?: string,"id"?: string,"registered_by"?: string | null,"session_id"?: string,"status"?: Database["public"]['Enums']["attendance_status"],"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "campaign_attendance_buyer_id_fkey"
      columns: ["buyer_id"]
isOneToOne: false
      referencedRelation: "buyers"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "campaign_attendance_campaign_id_fkey"
      columns: ["campaign_id"]
isOneToOne: false
      referencedRelation: "campaigns_jornadas"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "campaign_attendance_campaign_id_fkey"
      columns: ["campaign_id"]
isOneToOne: false
      referencedRelation: "v_campaign_margins"
      referencedColumns: ["campaign_id"]
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
      referencedRelation: "v_campaign_margins"
      referencedColumns: ["campaign_id"]
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
                    "agreement_id": string,"branch_id": string | null,"cancel_reason": string | null,"cancelled_at": string | null,"capture_closed_at": string | null,"capture_reopened_at": string | null,"city_id": string,"closed_at": string | null,"company_id": string,"created_at": string,"created_by": string | null,"deal_id": string,"id": string,"logistics_confirmed": boolean,"notes": string | null,"reopen_reason": string | null,"responsible_user_id": string,"scheduled_at": string | null,"started_at": string | null,"status": Database["public"]['Enums']["campaign_status"],"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "agreement_id": string,"branch_id"?: string | null,"cancel_reason"?: string | null,"cancelled_at"?: string | null,"capture_closed_at"?: string | null,"capture_reopened_at"?: string | null,"city_id": string,"closed_at"?: string | null,"company_id": string,"created_at"?: string,"created_by"?: string | null,"deal_id": string,"id"?: string,"logistics_confirmed"?: boolean,"notes"?: string | null,"reopen_reason"?: string | null,"responsible_user_id": string,"scheduled_at"?: string | null,"started_at"?: string | null,"status"?: Database["public"]['Enums']["campaign_status"],"updated_at"?: string
                  }
                  Update: {
                    "agreement_id"?: string,"branch_id"?: string | null,"cancel_reason"?: string | null,"cancelled_at"?: string | null,"capture_closed_at"?: string | null,"capture_reopened_at"?: string | null,"city_id"?: string,"closed_at"?: string | null,"company_id"?: string,"created_at"?: string,"created_by"?: string | null,"deal_id"?: string,"id"?: string,"logistics_confirmed"?: boolean,"notes"?: string | null,"reopen_reason"?: string | null,"responsible_user_id"?: string,"scheduled_at"?: string | null,"started_at"?: string | null,"status"?: Database["public"]['Enums']["campaign_status"],"updated_at"?: string
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
                },"collections_payments": {
                  Row: {
                    "bank_reference": string,"buyer_id": string | null,"company_id": string | null,"created_at": string,"id": string,"is_voided": boolean,"notes": string | null,"payment_date": string,"payment_number": number,"support_file_r2_key": string | null,"support_received": boolean,"total_received_bank": number,"updated_at": string,"verified_at": string,"verified_by": string | null,"void_reason": string | null,"voided_at": string | null,"voided_by": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "bank_reference": string,"buyer_id"?: string | null,"company_id"?: string | null,"created_at"?: string,"id"?: string,"is_voided"?: boolean,"notes"?: string | null,"payment_date": string,"payment_number"?: never,"support_file_r2_key"?: string | null,"support_received"?: boolean,"total_received_bank": number,"updated_at"?: string,"verified_at"?: string,"verified_by"?: string | null,"void_reason"?: string | null,"voided_at"?: string | null,"voided_by"?: string | null
                  }
                  Update: {
                    "bank_reference"?: string,"buyer_id"?: string | null,"company_id"?: string | null,"created_at"?: string,"id"?: string,"is_voided"?: boolean,"notes"?: string | null,"payment_date"?: string,"payment_number"?: never,"support_file_r2_key"?: string | null,"support_received"?: boolean,"total_received_bank"?: number,"updated_at"?: string,"verified_at"?: string,"verified_by"?: string | null,"void_reason"?: string | null,"voided_at"?: string | null,"voided_by"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "collections_payments_buyer_id_fkey"
      columns: ["buyer_id"]
isOneToOne: false
      referencedRelation: "buyers"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "collections_payments_company_id_fkey"
      columns: ["company_id"]
isOneToOne: false
      referencedRelation: "companies"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "collections_payments_verified_by_fkey"
      columns: ["verified_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "collections_payments_voided_by_fkey"
      columns: ["voided_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    }
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
                },"order_costs": {
                  Row: {
                    "amount": number,"basis": Database["public"]['Enums']["cost_basis"],"component": Database["public"]['Enums']["cost_component"],"created_at": string,"created_by": string | null,"id": string,"is_voided": boolean,"lab_provider_id": string | null,"notes": string | null,"order_id": string,"order_item_id": string | null,"replaces_id": string | null,"source": string,"superseded_at": string | null,"void_reason": string | null,"voided_at": string | null,"voided_by": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "amount": number,"basis": Database["public"]['Enums']["cost_basis"],"component": Database["public"]['Enums']["cost_component"],"created_at"?: string,"created_by"?: string | null,"id"?: string,"is_voided"?: boolean,"lab_provider_id"?: string | null,"notes"?: string | null,"order_id": string,"order_item_id"?: string | null,"replaces_id"?: string | null,"source": string,"superseded_at"?: string | null,"void_reason"?: string | null,"voided_at"?: string | null,"voided_by"?: string | null
                  }
                  Update: {
                    "amount"?: number,"basis"?: Database["public"]['Enums']["cost_basis"],"component"?: Database["public"]['Enums']["cost_component"],"created_at"?: string,"created_by"?: string | null,"id"?: string,"is_voided"?: boolean,"lab_provider_id"?: string | null,"notes"?: string | null,"order_id"?: string,"order_item_id"?: string | null,"replaces_id"?: string | null,"source"?: string,"superseded_at"?: string | null,"void_reason"?: string | null,"voided_at"?: string | null,"voided_by"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "order_costs_created_by_fkey"
      columns: ["created_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_costs_item_same_order"
      columns: ["order_item_id","order_id"]
isOneToOne: false
      referencedRelation: "order_items"
      referencedColumns: ["id","order_id"]
    },{
      foreignKeyName: "order_costs_item_same_order"
      columns: ["order_item_id","order_id"]
isOneToOne: false
      referencedRelation: "v_order_item_delivery"
      referencedColumns: ["order_item_id","order_id"]
    },{
      foreignKeyName: "order_costs_lab_provider_id_fkey"
      columns: ["lab_provider_id"]
isOneToOne: false
      referencedRelation: "lab_providers"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_costs_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_costs_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_order_margins"
      referencedColumns: ["order_id"]
    },{
      foreignKeyName: "order_costs_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_costs_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders_to_invoice"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_costs_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_receivables"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_costs_replaces_same_order"
      columns: ["replaces_id","order_id"]
isOneToOne: false
      referencedRelation: "order_costs"
      referencedColumns: ["id","order_id"]
    },{
      foreignKeyName: "order_costs_replaces_same_order"
      columns: ["replaces_id","order_id"]
isOneToOne: false
      referencedRelation: "v_order_costs"
      referencedColumns: ["id","order_id"]
    },{
      foreignKeyName: "order_costs_voided_by_fkey"
      columns: ["voided_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"order_deliveries": {
                  Row: {
                    "created_at": string,"delivered_at": string,"delivered_by": string | null,"delivery_evidence_r2_key": string | null,"evidence_received": boolean,"id": string,"notes": string | null,"order_id": string,"production_id": string | null,"receiver_name": string,"updated_at": string,"warranty_id": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"delivered_at"?: string,"delivered_by"?: string | null,"delivery_evidence_r2_key"?: string | null,"evidence_received"?: boolean,"id"?: string,"notes"?: string | null,"order_id": string,"production_id"?: string | null,"receiver_name": string,"updated_at"?: string,"warranty_id"?: string | null
                  }
                  Update: {
                    "created_at"?: string,"delivered_at"?: string,"delivered_by"?: string | null,"delivery_evidence_r2_key"?: string | null,"evidence_received"?: boolean,"id"?: string,"notes"?: string | null,"order_id"?: string,"production_id"?: string | null,"receiver_name"?: string,"updated_at"?: string,"warranty_id"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "order_deliveries_delivered_by_fkey"
      columns: ["delivered_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_deliveries_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_deliveries_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_order_margins"
      referencedColumns: ["order_id"]
    },{
      foreignKeyName: "order_deliveries_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_deliveries_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders_to_invoice"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_deliveries_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_receivables"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_deliveries_production_same_order"
      columns: ["production_id","order_id"]
isOneToOne: false
      referencedRelation: "order_productions"
      referencedColumns: ["id","order_id"]
    },{
      foreignKeyName: "order_deliveries_production_same_order"
      columns: ["production_id","order_id"]
isOneToOne: false
      referencedRelation: "v_productions"
      referencedColumns: ["id","order_id"]
    },{
      foreignKeyName: "order_deliveries_warranty_same_order"
      columns: ["warranty_id","order_id"]
isOneToOne: false
      referencedRelation: "post_sale_warranties"
      referencedColumns: ["id","order_id"]
    },{
      foreignKeyName: "order_deliveries_warranty_same_order"
      columns: ["warranty_id","order_id"]
isOneToOne: false
      referencedRelation: "v_warranties"
      referencedColumns: ["id","order_id"]
    }
                  ]
                },"order_delivery_items": {
                  Row: {
                    "created_at": string,"delivery_id": string,"id": string,"order_id": string,"order_item_id": string,"quantity": number
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"delivery_id": string,"id"?: string,"order_id": string,"order_item_id": string,"quantity": number
                  }
                  Update: {
                    "created_at"?: string,"delivery_id"?: string,"id"?: string,"order_id"?: string,"order_item_id"?: string,"quantity"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "order_delivery_items_delivery_same_order"
      columns: ["delivery_id","order_id"]
isOneToOne: false
      referencedRelation: "order_deliveries"
      referencedColumns: ["id","order_id"]
    },{
      foreignKeyName: "order_delivery_items_item_same_order"
      columns: ["order_item_id","order_id"]
isOneToOne: false
      referencedRelation: "order_items"
      referencedColumns: ["id","order_id"]
    },{
      foreignKeyName: "order_delivery_items_item_same_order"
      columns: ["order_item_id","order_id"]
isOneToOne: false
      referencedRelation: "v_order_item_delivery"
      referencedColumns: ["order_item_id","order_id"]
    }
                  ]
                },"order_installments": {
                  Row: {
                    "created_at": string,"due_date": string,"expected_amount": number,"id": string,"installment_number": number,"order_id": string,"paid_amount": number,"superseded_by_reclassification_id": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"due_date": string,"expected_amount": number,"id"?: string,"installment_number": number,"order_id": string,"paid_amount"?: number,"superseded_by_reclassification_id"?: string | null
                  }
                  Update: {
                    "created_at"?: string,"due_date"?: string,"expected_amount"?: number,"id"?: string,"installment_number"?: number,"order_id"?: string,"paid_amount"?: number,"superseded_by_reclassification_id"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "order_installments_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_installments_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_order_margins"
      referencedColumns: ["order_id"]
    },{
      foreignKeyName: "order_installments_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_installments_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders_to_invoice"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_installments_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_receivables"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_installments_reclassification_fkey"
      columns: ["superseded_by_reclassification_id"]
isOneToOne: false
      referencedRelation: "portfolio_reclassifications"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_installments_reclassification_fkey"
      columns: ["superseded_by_reclassification_id"]
isOneToOne: false
      referencedRelation: "v_portfolio_reclassifications"
      referencedColumns: ["id"]
    }
                  ]
                },"order_items": {
                  Row: {
                    "created_at": string,"description": string | null,"frame_description": string | null,"id": string,"item_type": Database["public"]['Enums']["order_item_type"],"lens_filter": string | null,"lens_type": string | null,"line_total": number | null,"order_id": string,"quantity": number,"unit_price": number,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"description"?: string | null,"frame_description"?: string | null,"id"?: string,"item_type": Database["public"]['Enums']["order_item_type"],"lens_filter"?: string | null,"lens_type"?: string | null,"line_total"?: never,"order_id": string,"quantity": number,"unit_price": number,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"description"?: string | null,"frame_description"?: string | null,"id"?: string,"item_type"?: Database["public"]['Enums']["order_item_type"],"lens_filter"?: string | null,"lens_type"?: string | null,"line_total"?: never,"order_id"?: string,"quantity"?: number,"unit_price"?: number,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "order_items_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_items_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_order_margins"
      referencedColumns: ["order_id"]
    },{
      foreignKeyName: "order_items_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_items_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders_to_invoice"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_items_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_receivables"
      referencedColumns: ["id"]
    }
                  ]
                },"order_productions": {
                  Row: {
                    "cancel_reason": string | null,"created_at": string,"id": string,"lab_provider_id": string,"notes": string | null,"order_id": string,"promised_date": string,"ready_at": string | null,"released_at": string,"released_by": string | null,"sent_to_lab_at": string,"status": Database["public"]['Enums']["production_status"],"updated_at": string,"warranty_id": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "cancel_reason"?: string | null,"created_at"?: string,"id"?: string,"lab_provider_id": string,"notes"?: string | null,"order_id": string,"promised_date": string,"ready_at"?: string | null,"released_at"?: string,"released_by"?: string | null,"sent_to_lab_at"?: string,"status"?: Database["public"]['Enums']["production_status"],"updated_at"?: string,"warranty_id"?: string | null
                  }
                  Update: {
                    "cancel_reason"?: string | null,"created_at"?: string,"id"?: string,"lab_provider_id"?: string,"notes"?: string | null,"order_id"?: string,"promised_date"?: string,"ready_at"?: string | null,"released_at"?: string,"released_by"?: string | null,"sent_to_lab_at"?: string,"status"?: Database["public"]['Enums']["production_status"],"updated_at"?: string,"warranty_id"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "order_productions_lab_provider_id_fkey"
      columns: ["lab_provider_id"]
isOneToOne: false
      referencedRelation: "lab_providers"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_productions_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_productions_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_order_margins"
      referencedColumns: ["order_id"]
    },{
      foreignKeyName: "order_productions_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_productions_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders_to_invoice"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_productions_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_receivables"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_productions_released_by_fkey"
      columns: ["released_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_productions_warranty_same_order"
      columns: ["warranty_id","order_id"]
isOneToOne: false
      referencedRelation: "post_sale_warranties"
      referencedColumns: ["id","order_id"]
    },{
      foreignKeyName: "order_productions_warranty_same_order"
      columns: ["warranty_id","order_id"]
isOneToOne: false
      referencedRelation: "v_warranties"
      referencedColumns: ["id","order_id"]
    }
                  ]
                },"orders": {
                  Row: {
                    "accounting_status": Database["public"]['Enums']["order_accounting_status"],"agreement_id": string | null,"balance_due": number,"branch_id": string | null,"buyer_id": string,"campaign_id": string | null,"cancel_reason": string | null,"cancelled_at": string | null,"cancelled_by": string | null,"city_id": string | null,"collection_responsible": Database["public"]['Enums']["collection_responsible"],"collection_status": Database["public"]['Enums']["order_collection_status"],"company_id": string | null,"created_at": string,"created_by": string | null,"doc_status": Database["public"]['Enums']["order_doc_status"],"employee_auth_file_r2_key": string | null,"employee_auth_received": boolean,"first_due_date": string | null,"historical_collected_before_migration": number,"historical_delivered_at": string | null,"historical_delivery_receiver": string | null,"historical_reference": string | null,"historical_stage": Database["public"]['Enums']["historical_stage"] | null,"hr_approval_r2_key": string | null,"hr_approval_received": boolean,"id": string,"installment_periodicity": Database["public"]['Enums']["payroll_frequency"] | null,"installments_count": number | null,"is_cancelled": boolean,"is_historical_migration": boolean,"notes": string | null,"ops_status": Database["public"]['Enums']["order_ops_status"],"order_number": number,"payment_modality": Database["public"]['Enums']["payment_modality"],"prepayment_exception_at": string | null,"prepayment_exception_by": string | null,"prepayment_exception_reason": string | null,"requirements_verified": boolean,"requirements_verified_at": string | null,"requirements_verified_by": string | null,"total_amount": number,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "accounting_status"?: Database["public"]['Enums']["order_accounting_status"],"agreement_id"?: string | null,"balance_due"?: number,"branch_id"?: string | null,"buyer_id": string,"campaign_id"?: string | null,"cancel_reason"?: string | null,"cancelled_at"?: string | null,"cancelled_by"?: string | null,"city_id"?: string | null,"collection_responsible"?: Database["public"]['Enums']["collection_responsible"],"collection_status"?: Database["public"]['Enums']["order_collection_status"],"company_id"?: string | null,"created_at"?: string,"created_by"?: string | null,"doc_status"?: Database["public"]['Enums']["order_doc_status"],"employee_auth_file_r2_key"?: string | null,"employee_auth_received"?: boolean,"first_due_date"?: string | null,"historical_collected_before_migration"?: number,"historical_delivered_at"?: string | null,"historical_delivery_receiver"?: string | null,"historical_reference"?: string | null,"historical_stage"?: Database["public"]['Enums']["historical_stage"] | null,"hr_approval_r2_key"?: string | null,"hr_approval_received"?: boolean,"id"?: string,"installment_periodicity"?: Database["public"]['Enums']["payroll_frequency"] | null,"installments_count"?: number | null,"is_cancelled"?: boolean,"is_historical_migration"?: boolean,"notes"?: string | null,"ops_status"?: Database["public"]['Enums']["order_ops_status"],"order_number"?: never,"payment_modality": Database["public"]['Enums']["payment_modality"],"prepayment_exception_at"?: string | null,"prepayment_exception_by"?: string | null,"prepayment_exception_reason"?: string | null,"requirements_verified"?: boolean,"requirements_verified_at"?: string | null,"requirements_verified_by"?: string | null,"total_amount"?: number,"updated_at"?: string
                  }
                  Update: {
                    "accounting_status"?: Database["public"]['Enums']["order_accounting_status"],"agreement_id"?: string | null,"balance_due"?: number,"branch_id"?: string | null,"buyer_id"?: string,"campaign_id"?: string | null,"cancel_reason"?: string | null,"cancelled_at"?: string | null,"cancelled_by"?: string | null,"city_id"?: string | null,"collection_responsible"?: Database["public"]['Enums']["collection_responsible"],"collection_status"?: Database["public"]['Enums']["order_collection_status"],"company_id"?: string | null,"created_at"?: string,"created_by"?: string | null,"doc_status"?: Database["public"]['Enums']["order_doc_status"],"employee_auth_file_r2_key"?: string | null,"employee_auth_received"?: boolean,"first_due_date"?: string | null,"historical_collected_before_migration"?: number,"historical_delivered_at"?: string | null,"historical_delivery_receiver"?: string | null,"historical_reference"?: string | null,"historical_stage"?: Database["public"]['Enums']["historical_stage"] | null,"hr_approval_r2_key"?: string | null,"hr_approval_received"?: boolean,"id"?: string,"installment_periodicity"?: Database["public"]['Enums']["payroll_frequency"] | null,"installments_count"?: number | null,"is_cancelled"?: boolean,"is_historical_migration"?: boolean,"notes"?: string | null,"ops_status"?: Database["public"]['Enums']["order_ops_status"],"order_number"?: never,"payment_modality"?: Database["public"]['Enums']["payment_modality"],"prepayment_exception_at"?: string | null,"prepayment_exception_by"?: string | null,"prepayment_exception_reason"?: string | null,"requirements_verified"?: boolean,"requirements_verified_at"?: string | null,"requirements_verified_by"?: string | null,"total_amount"?: number,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "orders_agreement_same_company"
      columns: ["agreement_id","company_id"]
isOneToOne: false
      referencedRelation: "agreements_convenios"
      referencedColumns: ["id","company_id"]
    },{
      foreignKeyName: "orders_agreement_same_company"
      columns: ["agreement_id","company_id"]
isOneToOne: false
      referencedRelation: "v_agreements"
      referencedColumns: ["id","company_id"]
    },{
      foreignKeyName: "orders_branch_same_company"
      columns: ["branch_id","company_id"]
isOneToOne: false
      referencedRelation: "company_branches"
      referencedColumns: ["id","company_id"]
    },{
      foreignKeyName: "orders_buyer_id_fkey"
      columns: ["buyer_id"]
isOneToOne: false
      referencedRelation: "buyers"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "orders_campaign_id_fkey"
      columns: ["campaign_id"]
isOneToOne: false
      referencedRelation: "campaigns_jornadas"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "orders_campaign_id_fkey"
      columns: ["campaign_id"]
isOneToOne: false
      referencedRelation: "v_campaign_margins"
      referencedColumns: ["campaign_id"]
    },{
      foreignKeyName: "orders_campaign_id_fkey"
      columns: ["campaign_id"]
isOneToOne: false
      referencedRelation: "v_campaigns"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "orders_cancelled_by_fkey"
      columns: ["cancelled_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "orders_city_id_fkey"
      columns: ["city_id"]
isOneToOne: false
      referencedRelation: "cities"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "orders_company_id_fkey"
      columns: ["company_id"]
isOneToOne: false
      referencedRelation: "companies"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "orders_created_by_fkey"
      columns: ["created_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "orders_prepayment_exception_by_fkey"
      columns: ["prepayment_exception_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "orders_requirements_verified_by_fkey"
      columns: ["requirements_verified_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"payment_allocations": {
                  Row: {
                    "amount_applied": number,"created_at": string,"created_by": string | null,"id": string,"installment_id": string | null,"is_voided": boolean,"order_id": string,"payment_id": string,"void_reason": string | null,"voided_at": string | null,"voided_by": string | null,"withholding_applied": number,"withholding_certificate_r2_key": string | null,"withholding_certificate_received": boolean
                  }
                  ComputedFields: never
                  Insert: {
                    "amount_applied"?: number,"created_at"?: string,"created_by"?: string | null,"id"?: string,"installment_id"?: string | null,"is_voided"?: boolean,"order_id": string,"payment_id": string,"void_reason"?: string | null,"voided_at"?: string | null,"voided_by"?: string | null,"withholding_applied"?: number,"withholding_certificate_r2_key"?: string | null,"withholding_certificate_received"?: boolean
                  }
                  Update: {
                    "amount_applied"?: number,"created_at"?: string,"created_by"?: string | null,"id"?: string,"installment_id"?: string | null,"is_voided"?: boolean,"order_id"?: string,"payment_id"?: string,"void_reason"?: string | null,"voided_at"?: string | null,"voided_by"?: string | null,"withholding_applied"?: number,"withholding_certificate_r2_key"?: string | null,"withholding_certificate_received"?: boolean
                  }
                  Relationships: [
                    {
      foreignKeyName: "payment_allocations_created_by_fkey"
      columns: ["created_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payment_allocations_installment_id_fkey"
      columns: ["installment_id"]
isOneToOne: false
      referencedRelation: "order_installments"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payment_allocations_installment_id_fkey"
      columns: ["installment_id"]
isOneToOne: false
      referencedRelation: "v_order_installments"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payment_allocations_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payment_allocations_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_order_margins"
      referencedColumns: ["order_id"]
    },{
      foreignKeyName: "payment_allocations_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payment_allocations_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders_to_invoice"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payment_allocations_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_receivables"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payment_allocations_payment_id_fkey"
      columns: ["payment_id"]
isOneToOne: false
      referencedRelation: "collections_payments"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payment_allocations_payment_id_fkey"
      columns: ["payment_id"]
isOneToOne: false
      referencedRelation: "v_payments"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payment_allocations_voided_by_fkey"
      columns: ["voided_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"portfolio_reclassifications": {
                  Row: {
                    "balance_at_request": number,"balance_transferred": number | null,"decided_at": string | null,"decided_by": string | null,"decision_notes": string | null,"from_responsible": Database["public"]['Enums']["collection_responsible"],"id": string,"new_first_due_date": string,"new_installments_count": number,"new_periodicity": Database["public"]['Enums']["payroll_frequency"],"notes": string | null,"order_id": string,"reason": Database["public"]['Enums']["reclassification_reason"],"requested_at": string,"requested_by": string | null,"status": Database["public"]['Enums']["reclassification_status"],"to_responsible": Database["public"]['Enums']["collection_responsible"]
                  }
                  ComputedFields: never
                  Insert: {
                    "balance_at_request"?: number,"balance_transferred"?: number | null,"decided_at"?: string | null,"decided_by"?: string | null,"decision_notes"?: string | null,"from_responsible"?: Database["public"]['Enums']["collection_responsible"],"id"?: string,"new_first_due_date": string,"new_installments_count": number,"new_periodicity": Database["public"]['Enums']["payroll_frequency"],"notes"?: string | null,"order_id": string,"reason": Database["public"]['Enums']["reclassification_reason"],"requested_at"?: string,"requested_by"?: string | null,"status"?: Database["public"]['Enums']["reclassification_status"],"to_responsible"?: Database["public"]['Enums']["collection_responsible"]
                  }
                  Update: {
                    "balance_at_request"?: number,"balance_transferred"?: number | null,"decided_at"?: string | null,"decided_by"?: string | null,"decision_notes"?: string | null,"from_responsible"?: Database["public"]['Enums']["collection_responsible"],"id"?: string,"new_first_due_date"?: string,"new_installments_count"?: number,"new_periodicity"?: Database["public"]['Enums']["payroll_frequency"],"notes"?: string | null,"order_id"?: string,"reason"?: Database["public"]['Enums']["reclassification_reason"],"requested_at"?: string,"requested_by"?: string | null,"status"?: Database["public"]['Enums']["reclassification_status"],"to_responsible"?: Database["public"]['Enums']["collection_responsible"]
                  }
                  Relationships: [
                    {
      foreignKeyName: "portfolio_reclassifications_decided_by_fkey"
      columns: ["decided_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "portfolio_reclassifications_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "portfolio_reclassifications_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_order_margins"
      referencedColumns: ["order_id"]
    },{
      foreignKeyName: "portfolio_reclassifications_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "portfolio_reclassifications_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders_to_invoice"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "portfolio_reclassifications_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_receivables"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "portfolio_reclassifications_requested_by_fkey"
      columns: ["requested_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"post_sale_warranties": {
                  Row: {
                    "closed_at": string | null,"closed_by": string | null,"created_at": string,"description": string,"evidence_r2_key": string | null,"evidence_received": boolean,"id": string,"incident_type": Database["public"]['Enums']["warranty_incident_type"],"opened_by": string | null,"order_id": string,"resolution": string | null,"responsible_user_id": string,"status": Database["public"]['Enums']["warranty_status"],"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "closed_at"?: string | null,"closed_by"?: string | null,"created_at"?: string,"description": string,"evidence_r2_key"?: string | null,"evidence_received"?: boolean,"id"?: string,"incident_type": Database["public"]['Enums']["warranty_incident_type"],"opened_by"?: string | null,"order_id": string,"resolution"?: string | null,"responsible_user_id": string,"status"?: Database["public"]['Enums']["warranty_status"],"updated_at"?: string
                  }
                  Update: {
                    "closed_at"?: string | null,"closed_by"?: string | null,"created_at"?: string,"description"?: string,"evidence_r2_key"?: string | null,"evidence_received"?: boolean,"id"?: string,"incident_type"?: Database["public"]['Enums']["warranty_incident_type"],"opened_by"?: string | null,"order_id"?: string,"resolution"?: string | null,"responsible_user_id"?: string,"status"?: Database["public"]['Enums']["warranty_status"],"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "post_sale_warranties_closed_by_fkey"
      columns: ["closed_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "post_sale_warranties_opened_by_fkey"
      columns: ["opened_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "post_sale_warranties_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "post_sale_warranties_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_order_margins"
      referencedColumns: ["order_id"]
    },{
      foreignKeyName: "post_sale_warranties_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "post_sale_warranties_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders_to_invoice"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "post_sale_warranties_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_receivables"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "post_sale_warranties_responsible_user_id_fkey"
      columns: ["responsible_user_id"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    }
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
      referencedRelation: "v_campaign_margins"
      referencedColumns: ["campaign_id"]
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
                },"v_campaign_margins": {
                  Row: {
                    "active_orders": number | null,"campaign_id": string,"cost_total": number | null,"has_estimated": boolean | null,"margin_amount": number | null,"margin_ratio": number | null,"orders_without_costs": number | null,"sold_amount": number | null
                  }
                  ComputedFields: never
                  Relationships: [
                    
                  ]
                },"v_campaigns": {
                  Row: {
                    "agreement_id": string,"attended_headcount": number | null,"branch_id": string | null,"branch_name": string | null,"cancel_reason": string | null,"cancelled_at": string | null,"capture_closed_at": string | null,"capture_reopened_at": string | null,"city_id": string,"city_name": string,"closed_at": string | null,"company_id": string,"company_name": string,"created_at": string,"deal_id": string,"deal_name_branch": string,"estimated_billing_amount": number | null,"first_session_date": string | null,"id": string,"last_session_date": string | null,"logistics_confirmed": boolean,"no_show_count": number | null,"notes": string | null,"reopen_reason": string | null,"responsible_user_id": string,"responsible_user_name": string,"scheduled_at": string | null,"scheduled_count": number | null,"sessions_count": number | null,"started_at": string | null,"status": Database["public"]['Enums']["campaign_status"],"target_employees_n": number | null,"updated_at": string
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
                },"v_invoice_orders": {
                  Row: {
                    "accounting_status": Database["public"]['Enums']["order_accounting_status"],"alegra_invoice_number": string,"amount_assigned": number,"buyer_document_id": string,"buyer_name": string,"created_at": string,"discrepancy_amount": number | null,"id": string,"invoice_date": string,"invoice_id": string,"invoice_voided": boolean,"order_billed_total": number | null,"order_cancelled": boolean,"order_difference": number | null,"order_id": string,"order_number": number,"order_total": number
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "alegra_invoice_orders_invoice_id_fkey"
      columns: ["invoice_id"]
isOneToOne: false
      referencedRelation: "alegra_invoices"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "alegra_invoice_orders_invoice_id_fkey"
      columns: ["invoice_id"]
isOneToOne: false
      referencedRelation: "v_invoices"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "alegra_invoice_orders_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "alegra_invoice_orders_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_order_margins"
      referencedColumns: ["order_id"]
    },{
      foreignKeyName: "alegra_invoice_orders_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "alegra_invoice_orders_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders_to_invoice"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "alegra_invoice_orders_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_receivables"
      referencedColumns: ["id"]
    }
                  ]
                },"v_invoices": {
                  Row: {
                    "alegra_discrepancy": boolean | null,"alegra_external_id": string | null,"alegra_invoice_number": string,"alegra_status": string | null,"alegra_sync_error": string | null,"alegra_synced_at": string | null,"alegra_total": number | null,"assigned_amount": number | null,"buyer_document_id": string | null,"buyer_id": string | null,"buyer_name": string | null,"company_id": string | null,"company_name": string | null,"company_nit": string | null,"created_at": string,"id": string,"invoice_date": string,"invoiced_amount": number,"is_voided": boolean,"notes": string | null,"orders_count": number | null,"orders_with_difference": number | null,"radication_status": Database["public"]['Enums']["invoice_radication_status"],"registered_by": string | null,"registered_by_name": string | null,"subject_name": string | null,"unassigned_amount": number | null,"updated_at": string,"void_reason": string | null,"voided_at": string | null
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "alegra_invoices_buyer_id_fkey"
      columns: ["buyer_id"]
isOneToOne: false
      referencedRelation: "buyers"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "alegra_invoices_company_id_fkey"
      columns: ["company_id"]
isOneToOne: false
      referencedRelation: "companies"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "alegra_invoices_registered_by_fkey"
      columns: ["registered_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"v_order_costs": {
                  Row: {
                    "amount": number,"basis": Database["public"]['Enums']["cost_basis"],"component": Database["public"]['Enums']["cost_component"],"created_at": string,"created_by": string | null,"created_by_name": string | null,"id": string,"is_current": boolean | null,"is_voided": boolean,"lab_provider_id": string | null,"lab_provider_name": string | null,"notes": string | null,"order_id": string,"order_item_id": string | null,"replaces_id": string | null,"source": string,"superseded_at": string | null,"void_reason": string | null,"voided_at": string | null
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "order_costs_created_by_fkey"
      columns: ["created_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_costs_item_same_order"
      columns: ["order_item_id","order_id"]
isOneToOne: false
      referencedRelation: "order_items"
      referencedColumns: ["id","order_id"]
    },{
      foreignKeyName: "order_costs_item_same_order"
      columns: ["order_item_id","order_id"]
isOneToOne: false
      referencedRelation: "v_order_item_delivery"
      referencedColumns: ["order_item_id","order_id"]
    },{
      foreignKeyName: "order_costs_lab_provider_id_fkey"
      columns: ["lab_provider_id"]
isOneToOne: false
      referencedRelation: "lab_providers"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_costs_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_costs_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_order_margins"
      referencedColumns: ["order_id"]
    },{
      foreignKeyName: "order_costs_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_costs_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders_to_invoice"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_costs_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_receivables"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_costs_replaces_same_order"
      columns: ["replaces_id","order_id"]
isOneToOne: false
      referencedRelation: "order_costs"
      referencedColumns: ["id","order_id"]
    },{
      foreignKeyName: "order_costs_replaces_same_order"
      columns: ["replaces_id","order_id"]
isOneToOne: false
      referencedRelation: "v_order_costs"
      referencedColumns: ["id","order_id"]
    }
                  ]
                },"v_order_installments": {
                  Row: {
                    "due_date": string,"expected_amount": number,"id": string,"installment_number": number,"order_id": string,"paid_amount": number,"pending_amount": number | null,"status": string | null,"superseded_by_reclassification_id": string | null
                  }
                  ComputedFields: never
                  Insert: {
                           "due_date"?: string | null,"expected_amount"?: number | null,"id"?: string | null,"installment_number"?: number | null,"order_id"?: string | null,"paid_amount"?: number | null,"pending_amount"?: never,"status"?: never,"superseded_by_reclassification_id"?: string | null
                         }
                        Update: {
                           "due_date"?: string | null,"expected_amount"?: number | null,"id"?: string | null,"installment_number"?: number | null,"order_id"?: string | null,"paid_amount"?: number | null,"pending_amount"?: never,"status"?: never,"superseded_by_reclassification_id"?: string | null
                         }
                        Relationships: [
                    {
      foreignKeyName: "order_installments_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_installments_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_order_margins"
      referencedColumns: ["order_id"]
    },{
      foreignKeyName: "order_installments_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_installments_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders_to_invoice"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_installments_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_receivables"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_installments_reclassification_fkey"
      columns: ["superseded_by_reclassification_id"]
isOneToOne: false
      referencedRelation: "portfolio_reclassifications"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_installments_reclassification_fkey"
      columns: ["superseded_by_reclassification_id"]
isOneToOne: false
      referencedRelation: "v_portfolio_reclassifications"
      referencedColumns: ["id"]
    }
                  ]
                },"v_order_item_delivery": {
                  Row: {
                    "delivered_quantity": number | null,"description": string | null,"frame_description": string | null,"item_type": Database["public"]['Enums']["order_item_type"],"lens_filter": string | null,"lens_type": string | null,"order_id": string,"order_item_id": string,"pending_quantity": number | null,"quantity": number
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "order_items_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_items_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_order_margins"
      referencedColumns: ["order_id"]
    },{
      foreignKeyName: "order_items_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_items_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders_to_invoice"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_items_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_receivables"
      referencedColumns: ["id"]
    }
                  ]
                },"v_order_margins": {
                  Row: {
                    "campaign_id": string | null,"company_id": string | null,"cost_basis": string | null,"cost_kit": number | null,"cost_lente": number | null,"cost_montura": number | null,"cost_otro": number | null,"cost_total": number | null,"costs_count": number | null,"is_cancelled": boolean,"margin_amount": number | null,"margin_ratio": number | null,"order_id": string,"order_number": number,"total_amount": number
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "orders_campaign_id_fkey"
      columns: ["campaign_id"]
isOneToOne: false
      referencedRelation: "campaigns_jornadas"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "orders_campaign_id_fkey"
      columns: ["campaign_id"]
isOneToOne: false
      referencedRelation: "v_campaign_margins"
      referencedColumns: ["campaign_id"]
    },{
      foreignKeyName: "orders_campaign_id_fkey"
      columns: ["campaign_id"]
isOneToOne: false
      referencedRelation: "v_campaigns"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "orders_company_id_fkey"
      columns: ["company_id"]
isOneToOne: false
      referencedRelation: "companies"
      referencedColumns: ["id"]
    }
                  ]
                },"v_orders": {
                  Row: {
                    "accounting_status": Database["public"]['Enums']["order_accounting_status"],"agreement_id": string | null,"balance_due": number,"branch_id": string | null,"branch_name": string | null,"buyer_document_id": string,"buyer_document_type": Database["public"]['Enums']["buyer_document_type"],"buyer_id": string,"buyer_name": string,"campaign_id": string | null,"campaign_status": Database["public"]['Enums']["campaign_status"] | null,"cancel_reason": string | null,"cancelled_at": string | null,"cancelled_by": string | null,"city_id": string | null,"city_name": string | null,"collection_responsible": Database["public"]['Enums']["collection_responsible"],"collection_status": Database["public"]['Enums']["order_collection_status"],"company_id": string | null,"company_name": string | null,"created_at": string,"created_by": string | null,"created_by_name": string | null,"deal_id": string | null,"deal_name_branch": string | null,"doc_status": Database["public"]['Enums']["order_doc_status"],"employee_auth_received": boolean,"first_due_date": string | null,"historical_collected_before_migration": number,"historical_delivered_at": string | null,"historical_delivery_receiver": string | null,"historical_reference": string | null,"historical_stage": Database["public"]['Enums']["historical_stage"] | null,"hr_approval_received": boolean,"hr_approval_required": boolean | null,"id": string,"installment_periodicity": Database["public"]['Enums']["payroll_frequency"] | null,"installments_count": number | null,"is_cancelled": boolean,"is_historical_migration": boolean,"items_count": number | null,"missing_requirements": (string)[] | null,"notes": string | null,"ops_status": Database["public"]['Enums']["order_ops_status"],"order_number": number,"payment_modality": Database["public"]['Enums']["payment_modality"],"prepayment_exception_at": string | null,"prepayment_exception_by": string | null,"prepayment_exception_reason": string | null,"release_blockers": (string)[] | null,"requirements_verified": boolean,"requirements_verified_at": string | null,"requirements_verified_by": string | null,"total_amount": number,"updated_at": string
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "orders_agreement_same_company"
      columns: ["agreement_id","company_id"]
isOneToOne: false
      referencedRelation: "agreements_convenios"
      referencedColumns: ["id","company_id"]
    },{
      foreignKeyName: "orders_agreement_same_company"
      columns: ["agreement_id","company_id"]
isOneToOne: false
      referencedRelation: "v_agreements"
      referencedColumns: ["id","company_id"]
    },{
      foreignKeyName: "orders_branch_same_company"
      columns: ["branch_id","company_id"]
isOneToOne: false
      referencedRelation: "company_branches"
      referencedColumns: ["id","company_id"]
    },{
      foreignKeyName: "orders_buyer_id_fkey"
      columns: ["buyer_id"]
isOneToOne: false
      referencedRelation: "buyers"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "orders_campaign_id_fkey"
      columns: ["campaign_id"]
isOneToOne: false
      referencedRelation: "campaigns_jornadas"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "orders_campaign_id_fkey"
      columns: ["campaign_id"]
isOneToOne: false
      referencedRelation: "v_campaign_margins"
      referencedColumns: ["campaign_id"]
    },{
      foreignKeyName: "orders_campaign_id_fkey"
      columns: ["campaign_id"]
isOneToOne: false
      referencedRelation: "v_campaigns"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "orders_cancelled_by_fkey"
      columns: ["cancelled_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "orders_city_id_fkey"
      columns: ["city_id"]
isOneToOne: false
      referencedRelation: "cities"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "orders_company_id_fkey"
      columns: ["company_id"]
isOneToOne: false
      referencedRelation: "companies"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "orders_created_by_fkey"
      columns: ["created_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "orders_prepayment_exception_by_fkey"
      columns: ["prepayment_exception_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "orders_requirements_verified_by_fkey"
      columns: ["requirements_verified_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"v_orders_to_invoice": {
                  Row: {
                    "accounting_status": Database["public"]['Enums']["order_accounting_status"],"billed_amount": number | null,"buyer_document_id": string,"buyer_id": string,"buyer_name": string,"company_id": string | null,"company_name": string | null,"company_nit_provisional": boolean | null,"created_at": string,"id": string,"ops_status": Database["public"]['Enums']["order_ops_status"],"order_number": number,"payment_modality": Database["public"]['Enums']["payment_modality"],"pending_amount": number | null,"total_amount": number
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "orders_buyer_id_fkey"
      columns: ["buyer_id"]
isOneToOne: false
      referencedRelation: "buyers"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "orders_company_id_fkey"
      columns: ["company_id"]
isOneToOne: false
      referencedRelation: "companies"
      referencedColumns: ["id"]
    }
                  ]
                },"v_payment_allocations": {
                  Row: {
                    "amount_applied": number,"bank_reference": string,"buyer_document_id": string,"buyer_name": string,"created_at": string,"created_by": string | null,"created_by_name": string | null,"id": string,"installment_due_date": string | null,"installment_id": string | null,"installment_number": number | null,"is_voided": boolean,"order_id": string,"order_number": number,"payment_date": string,"payment_id": string,"payment_number": number,"void_reason": string | null,"withholding_applied": number,"withholding_certificate_received": boolean
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "payment_allocations_created_by_fkey"
      columns: ["created_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payment_allocations_installment_id_fkey"
      columns: ["installment_id"]
isOneToOne: false
      referencedRelation: "order_installments"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payment_allocations_installment_id_fkey"
      columns: ["installment_id"]
isOneToOne: false
      referencedRelation: "v_order_installments"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payment_allocations_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payment_allocations_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_order_margins"
      referencedColumns: ["order_id"]
    },{
      foreignKeyName: "payment_allocations_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payment_allocations_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders_to_invoice"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payment_allocations_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_receivables"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payment_allocations_payment_id_fkey"
      columns: ["payment_id"]
isOneToOne: false
      referencedRelation: "collections_payments"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payment_allocations_payment_id_fkey"
      columns: ["payment_id"]
isOneToOne: false
      referencedRelation: "v_payments"
      referencedColumns: ["id"]
    }
                  ]
                },"v_payments": {
                  Row: {
                    "allocated_amount": number | null,"bank_reference": string,"buyer_document_id": string | null,"buyer_id": string | null,"company_id": string | null,"company_nit": string | null,"created_at": string,"id": string,"is_voided": boolean,"notes": string | null,"orders_count": number | null,"payer_name": string | null,"payment_date": string,"payment_number": number,"support_received": boolean,"total_received_bank": number,"unassigned_amount": number | null,"verified_at": string,"verified_by": string | null,"verified_by_name": string | null,"void_reason": string | null,"voided_at": string | null,"withholding_amount": number | null
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "collections_payments_buyer_id_fkey"
      columns: ["buyer_id"]
isOneToOne: false
      referencedRelation: "buyers"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "collections_payments_company_id_fkey"
      columns: ["company_id"]
isOneToOne: false
      referencedRelation: "companies"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "collections_payments_verified_by_fkey"
      columns: ["verified_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"v_portfolio_reclassifications": {
                  Row: {
                    "balance_at_request": number,"balance_transferred": number | null,"buyer_document_id": string,"buyer_id": string,"buyer_name": string,"company_id": string | null,"company_name": string | null,"current_balance": number,"decided_at": string | null,"decided_by": string | null,"decided_by_name": string | null,"decision_notes": string | null,"from_responsible": Database["public"]['Enums']["collection_responsible"],"id": string,"new_first_due_date": string,"new_installments_count": number,"new_periodicity": Database["public"]['Enums']["payroll_frequency"],"notes": string | null,"order_id": string,"order_number": number,"reason": Database["public"]['Enums']["reclassification_reason"],"requested_at": string,"requested_by": string | null,"requested_by_name": string | null,"status": Database["public"]['Enums']["reclassification_status"],"to_responsible": Database["public"]['Enums']["collection_responsible"]
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "orders_buyer_id_fkey"
      columns: ["buyer_id"]
isOneToOne: false
      referencedRelation: "buyers"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "orders_company_id_fkey"
      columns: ["company_id"]
isOneToOne: false
      referencedRelation: "companies"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "portfolio_reclassifications_decided_by_fkey"
      columns: ["decided_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "portfolio_reclassifications_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "portfolio_reclassifications_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_order_margins"
      referencedColumns: ["order_id"]
    },{
      foreignKeyName: "portfolio_reclassifications_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "portfolio_reclassifications_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders_to_invoice"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "portfolio_reclassifications_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_receivables"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "portfolio_reclassifications_requested_by_fkey"
      columns: ["requested_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"v_productions": {
                  Row: {
                    "buyer_document_id": string,"buyer_name": string,"cancel_reason": string | null,"city_name": string | null,"company_name": string | null,"id": string,"is_overdue": boolean | null,"lab_name": string,"lab_provider_id": string,"notes": string | null,"ops_status": Database["public"]['Enums']["order_ops_status"],"order_id": string,"order_number": number,"promised_date": string,"ready_at": string | null,"released_at": string,"released_by": string | null,"released_by_name": string | null,"sent_to_lab_at": string,"status": Database["public"]['Enums']["production_status"],"warranty_id": string | null
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "order_productions_lab_provider_id_fkey"
      columns: ["lab_provider_id"]
isOneToOne: false
      referencedRelation: "lab_providers"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_productions_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_productions_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_order_margins"
      referencedColumns: ["order_id"]
    },{
      foreignKeyName: "order_productions_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_productions_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders_to_invoice"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_productions_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_receivables"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_productions_released_by_fkey"
      columns: ["released_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_productions_warranty_same_order"
      columns: ["warranty_id","order_id"]
isOneToOne: false
      referencedRelation: "post_sale_warranties"
      referencedColumns: ["id","order_id"]
    },{
      foreignKeyName: "order_productions_warranty_same_order"
      columns: ["warranty_id","order_id"]
isOneToOne: false
      referencedRelation: "v_warranties"
      referencedColumns: ["id","order_id"]
    }
                  ]
                },"v_receivables": {
                  Row: {
                    "balance_due": number,"buyer_document_id": string,"buyer_id": string,"buyer_name": string,"collected_amount": number | null,"collection_responsible": Database["public"]['Enums']["collection_responsible"],"collection_status": Database["public"]['Enums']["order_collection_status"],"company_id": string | null,"company_name": string | null,"created_at": string,"id": string,"next_due_date": string | null,"order_number": number,"overdue_amount": number | null,"overdue_count": number | null,"payment_modality": Database["public"]['Enums']["payment_modality"],"total_amount": number
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "orders_buyer_id_fkey"
      columns: ["buyer_id"]
isOneToOne: false
      referencedRelation: "buyers"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "orders_company_id_fkey"
      columns: ["company_id"]
isOneToOne: false
      referencedRelation: "companies"
      referencedColumns: ["id"]
    }
                  ]
                },"v_warranties": {
                  Row: {
                    "buyer_document_id": string,"buyer_name": string,"closed_at": string | null,"closed_by": string | null,"closed_by_name": string | null,"company_name": string | null,"created_at": string,"description": string,"evidence_received": boolean,"id": string,"incident_type": Database["public"]['Enums']["warranty_incident_type"],"opened_by": string | null,"opened_by_name": string | null,"order_id": string,"order_number": number,"resolution": string | null,"responsible_name": string,"responsible_user_id": string,"status": Database["public"]['Enums']["warranty_status"],"updated_at": string
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "post_sale_warranties_closed_by_fkey"
      columns: ["closed_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "post_sale_warranties_opened_by_fkey"
      columns: ["opened_by"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "post_sale_warranties_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "post_sale_warranties_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_order_margins"
      referencedColumns: ["order_id"]
    },{
      foreignKeyName: "post_sale_warranties_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "post_sale_warranties_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders_to_invoice"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "post_sale_warranties_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_receivables"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "post_sale_warranties_responsible_user_id_fkey"
      columns: ["responsible_user_id"]
isOneToOne: false
      referencedRelation: "users_profiles"
      referencedColumns: ["id"]
    }
                  ]
                }
          }
          Functions: {
            "apply_payment":
{ Args: { "p_amount": number,"p_certificate_received"?: boolean,"p_order_id": string,"p_payment_id": string,"p_withholding"?: number }; Returns: number
                           },
"apply_payment_batch":
{ Args: { "p_items": Json,"p_payment_id": string }; Returns: number
                           },
"create_historical_order":
{ Args: { "p_items"?: Json,"p_order": Json }; Returns: string
                           },
"create_order":
{ Args: { "p_items": Json,"p_order": Json }; Returns: string
                           },
"find_company_duplicates":
{ Args: { "p_name": string,"p_nit"?: string }; Returns: {
              "id": string,"is_nit_provisional": boolean,"match_reason": string,"name": string,"nit": string,"similarity": number
            }[]
                           },
"recalculate_deal_forecast":
{ Args: { "p_deal_id": string }; Returns: number
                           },
"register_delivery":
{ Args: { "p_delivery": Json,"p_items": Json }; Returns: string
                           },
"register_historical_delivery":
{ Args: { "p_delivered_at": string,"p_order_id": string,"p_receiver": string }; Returns: undefined
                           }
          }
          Enums: {
            "agreement_document_type": "convenio_firmado"|"camara_comercio"|"rut"|"formato_rrhh"|"otro","agreement_status": "borrador"|"pendiente_aprobacion"|"aprobado"|"cancelado","app_role": "comercial"|"operacion"|"administracion_cartera"|"direccion"|"proveedor_lab"|"socio","attendance_status": "agendado"|"presente"|"atendido"|"no_asistio"|"cancelado","buyer_document_type": "cc"|"ce"|"ti"|"pasaporte"|"otro","campaign_status": "borrador"|"programada"|"en_ejecucion"|"captura_cerrada"|"operacion_cerrada"|"cancelada","collection_responsible": "empresa"|"empleado","contact_area": "rrhh"|"sst"|"gerencia"|"compras"|"otra","cost_basis": "estimado"|"verificado","cost_component": "lente"|"montura"|"kit"|"otro","deal_stage": "prospecto"|"reunion_exploratoria"|"propuesta_enviada"|"negociacion"|"convenio_firmado"|"jornada_en_ejecucion"|"facturacion_cerrada"|"cierre_perdido","historical_stage": "venta"|"produccion"|"entregada","interaction_type": "reunion"|"llamada"|"whatsapp"|"correo","invoice_radication_status": "pendiente"|"radicada"|"rechazada","lost_substatus": "nurturing"|"no_contactar","order_accounting_status": "pendiente_vincular"|"factura_vinculada"|"factura_con_diferencia","order_collection_status": "con_saldo"|"parcialmente_recaudado"|"recaudado_total","order_doc_status": "pendiente_soportes"|"requisitos_verificados","order_item_type": "gafas_completas"|"montura"|"lentes"|"otro","order_ops_status": "pendiente_liberar"|"en_produccion"|"listo_para_entregar"|"entrega_parcial"|"entrega_completa","payment_modality": "contado"|"nomina_empresa","payroll_frequency": "mensual"|"quincenal","production_status": "en_produccion"|"listo_para_entregar"|"cancelada","reclassification_reason": "retiro"|"incapacidad"|"otro","reclassification_status": "pendiente"|"autorizada"|"rechazada"|"anulada","warranty_incident_type": "garantia"|"reclamo"|"ajuste"|"otro","warranty_status": "abierta"|"en_reposicion"|"cerrada"
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
            "agreement_document_type": ["convenio_firmado", "camara_comercio", "rut", "formato_rrhh", "otro"],"agreement_status": ["borrador", "pendiente_aprobacion", "aprobado", "cancelado"],"app_role": ["comercial", "operacion", "administracion_cartera", "direccion", "proveedor_lab", "socio"],"attendance_status": ["agendado", "presente", "atendido", "no_asistio", "cancelado"],"buyer_document_type": ["cc", "ce", "ti", "pasaporte", "otro"],"campaign_status": ["borrador", "programada", "en_ejecucion", "captura_cerrada", "operacion_cerrada", "cancelada"],"collection_responsible": ["empresa", "empleado"],"contact_area": ["rrhh", "sst", "gerencia", "compras", "otra"],"cost_basis": ["estimado", "verificado"],"cost_component": ["lente", "montura", "kit", "otro"],"deal_stage": ["prospecto", "reunion_exploratoria", "propuesta_enviada", "negociacion", "convenio_firmado", "jornada_en_ejecucion", "facturacion_cerrada", "cierre_perdido"],"historical_stage": ["venta", "produccion", "entregada"],"interaction_type": ["reunion", "llamada", "whatsapp", "correo"],"invoice_radication_status": ["pendiente", "radicada", "rechazada"],"lost_substatus": ["nurturing", "no_contactar"],"order_accounting_status": ["pendiente_vincular", "factura_vinculada", "factura_con_diferencia"],"order_collection_status": ["con_saldo", "parcialmente_recaudado", "recaudado_total"],"order_doc_status": ["pendiente_soportes", "requisitos_verificados"],"order_item_type": ["gafas_completas", "montura", "lentes", "otro"],"order_ops_status": ["pendiente_liberar", "en_produccion", "listo_para_entregar", "entrega_parcial", "entrega_completa"],"payment_modality": ["contado", "nomina_empresa"],"payroll_frequency": ["mensual", "quincenal"],"production_status": ["en_produccion", "listo_para_entregar", "cancelada"],"reclassification_reason": ["retiro", "incapacidad", "otro"],"reclassification_status": ["pendiente", "autorizada", "rechazada", "anulada"],"warranty_incident_type": ["garantia", "reclamo", "ajuste", "otro"],"warranty_status": ["abierta", "en_reposicion", "cerrada"]
          }
        }
} as const
