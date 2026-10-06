export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json | null
          operationName?: string | null
          query?: string | null
          variables?: Json | null
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      actas_descanso_sustitutorio: {
        Row: {
          archivo_base64: string | null
          archivo_nombre: string | null
          created_at: string
          id: string
          referencia: string
          storage_path: string | null
          subida_por: string | null
          updated_at: string
        }
        Insert: {
          archivo_base64?: string | null
          archivo_nombre?: string | null
          created_at?: string
          id?: string
          referencia: string
          storage_path?: string | null
          subida_por?: string | null
          updated_at?: string
        }
        Update: {
          archivo_base64?: string | null
          archivo_nombre?: string | null
          created_at?: string
          id?: string
          referencia?: string
          storage_path?: string | null
          subida_por?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "actas_descanso_sustitutorio_subida_por_fkey"
            columns: ["subida_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "actas_descanso_sustitutorio_subida_por_fkey"
            columns: ["subida_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      alertas: {
        Row: {
          canal: string
          created_at: string
          enviado_at: string | null
          estado: string
          id: string
          intentos: number
          leido_at: string | null
          nota_fallo: string | null
          payload: Json
          persona_id: string | null
          procesando_desde: string | null
          tipo: string
          ultimo_intento_at: string | null
        }
        Insert: {
          canal: string
          created_at?: string
          enviado_at?: string | null
          estado?: string
          id?: string
          intentos?: number
          leido_at?: string | null
          nota_fallo?: string | null
          payload?: Json
          persona_id?: string | null
          procesando_desde?: string | null
          tipo: string
          ultimo_intento_at?: string | null
        }
        Update: {
          canal?: string
          created_at?: string
          enviado_at?: string | null
          estado?: string
          id?: string
          intentos?: number
          leido_at?: string | null
          nota_fallo?: string | null
          payload?: Json
          persona_id?: string | null
          procesando_desde?: string | null
          tipo?: string
          ultimo_intento_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "alertas_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "alertas_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      anuncios: {
        Row: {
          anulado_at: string | null
          anulado_por: string | null
          cuerpo: string
          id: string
          publicado_at: string
          publicado_por: string
          sede_id: string | null
          titulo: string
        }
        Insert: {
          anulado_at?: string | null
          anulado_por?: string | null
          cuerpo: string
          id?: string
          publicado_at?: string
          publicado_por: string
          sede_id?: string | null
          titulo: string
        }
        Update: {
          anulado_at?: string | null
          anulado_por?: string | null
          cuerpo?: string
          id?: string
          publicado_at?: string
          publicado_por?: string
          sede_id?: string | null
          titulo?: string
        }
        Relationships: [
          {
            foreignKeyName: "anuncios_anulado_por_fkey"
            columns: ["anulado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "anuncios_anulado_por_fkey"
            columns: ["anulado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "anuncios_publicado_por_fkey"
            columns: ["publicado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "anuncios_publicado_por_fkey"
            columns: ["publicado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "anuncios_sede_id_fkey"
            columns: ["sede_id"]
            isOneToOne: false
            referencedRelation: "sedes"
            referencedColumns: ["id"]
          },
        ]
      }
      anuncios_leidos: {
        Row: {
          anuncio_id: string
          leido_at: string
          persona_id: string
        }
        Insert: {
          anuncio_id: string
          leido_at?: string
          persona_id: string
        }
        Update: {
          anuncio_id?: string
          leido_at?: string
          persona_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "anuncios_leidos_anuncio_id_fkey"
            columns: ["anuncio_id"]
            isOneToOne: false
            referencedRelation: "anuncios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "anuncios_leidos_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "anuncios_leidos_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      archivo_empresa: {
        Row: {
          bytes: number
          entidad: string
          fecha_documento: string
          id: string
          mime: string
          nombre_archivo: string
          nota: string | null
          numero: string | null
          reemplaza_a: string | null
          retirado_at: string | null
          retirado_motivo: string | null
          retirado_por: string | null
          sede_id: string | null
          storage_path: string
          subido_at: string
          subido_por: string
          titulo: string
          vence_el: string | null
        }
        Insert: {
          bytes: number
          entidad: string
          fecha_documento: string
          id?: string
          mime: string
          nombre_archivo: string
          nota?: string | null
          numero?: string | null
          reemplaza_a?: string | null
          retirado_at?: string | null
          retirado_motivo?: string | null
          retirado_por?: string | null
          sede_id?: string | null
          storage_path: string
          subido_at?: string
          subido_por: string
          titulo: string
          vence_el?: string | null
        }
        Update: {
          bytes?: number
          entidad?: string
          fecha_documento?: string
          id?: string
          mime?: string
          nombre_archivo?: string
          nota?: string | null
          numero?: string | null
          reemplaza_a?: string | null
          retirado_at?: string | null
          retirado_motivo?: string | null
          retirado_por?: string | null
          sede_id?: string | null
          storage_path?: string
          subido_at?: string
          subido_por?: string
          titulo?: string
          vence_el?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "archivo_empresa_reemplaza_a_fkey"
            columns: ["reemplaza_a"]
            isOneToOne: false
            referencedRelation: "archivo_empresa"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "archivo_empresa_retirado_por_fkey"
            columns: ["retirado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "archivo_empresa_retirado_por_fkey"
            columns: ["retirado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "archivo_empresa_sede_id_fkey"
            columns: ["sede_id"]
            isOneToOne: false
            referencedRelation: "sedes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "archivo_empresa_subido_por_fkey"
            columns: ["subido_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "archivo_empresa_subido_por_fkey"
            columns: ["subido_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      areas: {
        Row: {
          activa: boolean
          codigo: string
          created_at: string
          nombre: string
          operativa: boolean
          orden: number
        }
        Insert: {
          activa?: boolean
          codigo: string
          created_at?: string
          nombre: string
          operativa?: boolean
          orden?: number
        }
        Update: {
          activa?: boolean
          codigo?: string
          created_at?: string
          nombre?: string
          operativa?: boolean
          orden?: number
        }
        Relationships: []
      }
      asignaciones_educacion: {
        Row: {
          beneficiario: string
          beneficiario_nombre: string | null
          cobertura_pct: number
          comprobante_url: string | null
          costo_declarado: number
          created_at: string
          familia_id: string
          frecuencia_pago: string | null
          id: string
          institucion: string
          monto: number
          nota: string | null
          persona_id: string
          proxima_fecha_pago: string | null
          registrado_por: string | null
          vigente_desde: string
          vigente_hasta: string
        }
        Insert: {
          beneficiario?: string
          beneficiario_nombre?: string | null
          cobertura_pct?: number
          comprobante_url?: string | null
          costo_declarado: number
          created_at?: string
          familia_id: string
          frecuencia_pago?: string | null
          id?: string
          institucion: string
          monto: number
          nota?: string | null
          persona_id: string
          proxima_fecha_pago?: string | null
          registrado_por?: string | null
          vigente_desde: string
          vigente_hasta: string
        }
        Update: {
          beneficiario?: string
          beneficiario_nombre?: string | null
          cobertura_pct?: number
          comprobante_url?: string | null
          costo_declarado?: number
          created_at?: string
          familia_id?: string
          frecuencia_pago?: string | null
          id?: string
          institucion?: string
          monto?: number
          nota?: string | null
          persona_id?: string
          proxima_fecha_pago?: string | null
          registrado_por?: string | null
          vigente_desde?: string
          vigente_hasta?: string
        }
        Relationships: [
          {
            foreignKeyName: "asignaciones_educacion_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asignaciones_educacion_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asignaciones_educacion_registrado_por_fkey"
            columns: ["registrado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asignaciones_educacion_registrado_por_fkey"
            columns: ["registrado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      asignaciones_regimen_pension: {
        Row: {
          asignado_por: string | null
          created_at: string
          id: string
          nota: string | null
          persona_id: string
          regimen: string
          vigente_desde: string
          vigente_hasta: string | null
        }
        Insert: {
          asignado_por?: string | null
          created_at?: string
          id?: string
          nota?: string | null
          persona_id: string
          regimen: string
          vigente_desde: string
          vigente_hasta?: string | null
        }
        Update: {
          asignado_por?: string | null
          created_at?: string
          id?: string
          nota?: string | null
          persona_id?: string
          regimen?: string
          vigente_desde?: string
          vigente_hasta?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "asignaciones_regimen_pension_asignado_por_fkey"
            columns: ["asignado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asignaciones_regimen_pension_asignado_por_fkey"
            columns: ["asignado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asignaciones_regimen_pension_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asignaciones_regimen_pension_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      asignaciones_salario: {
        Row: {
          asignado_por: string | null
          base_provision: number | null
          created_at: string
          id: string
          nota: string | null
          persona_id: string
          rango: string
          salario_mensual_soles: number
          vigente_desde: string
          vigente_hasta: string | null
        }
        Insert: {
          asignado_por?: string | null
          base_provision?: number | null
          created_at?: string
          id?: string
          nota?: string | null
          persona_id: string
          rango: string
          salario_mensual_soles: number
          vigente_desde: string
          vigente_hasta?: string | null
        }
        Update: {
          asignado_por?: string | null
          base_provision?: number | null
          created_at?: string
          id?: string
          nota?: string | null
          persona_id?: string
          rango?: string
          salario_mensual_soles?: number
          vigente_desde?: string
          vigente_hasta?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "asignaciones_salario_asignado_por_fkey"
            columns: ["asignado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asignaciones_salario_asignado_por_fkey"
            columns: ["asignado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asignaciones_salario_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asignaciones_salario_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      ausencias: {
        Row: {
          anulada_at: string | null
          anulada_motivo: string | null
          anulada_por: string | null
          aprobada_at: string | null
          aprobada_por: string | null
          doc_colegiatura: string | null
          doc_fecha: string | null
          doc_profesional: string | null
          doc_storage_path: string | null
          fecha_fin: string
          fecha_inicio: string
          id: string
          motivo: string | null
          persona_id: string
          registrada_at: string
          registrada_por: string
          registrada_tarde: boolean
          subsidio_diario: number | null
          tipo: string
        }
        Insert: {
          anulada_at?: string | null
          anulada_motivo?: string | null
          anulada_por?: string | null
          aprobada_at?: string | null
          aprobada_por?: string | null
          doc_colegiatura?: string | null
          doc_fecha?: string | null
          doc_profesional?: string | null
          doc_storage_path?: string | null
          fecha_fin: string
          fecha_inicio: string
          id?: string
          motivo?: string | null
          persona_id: string
          registrada_at?: string
          registrada_por: string
          registrada_tarde?: boolean
          subsidio_diario?: number | null
          tipo: string
        }
        Update: {
          anulada_at?: string | null
          anulada_motivo?: string | null
          anulada_por?: string | null
          aprobada_at?: string | null
          aprobada_por?: string | null
          doc_colegiatura?: string | null
          doc_fecha?: string | null
          doc_profesional?: string | null
          doc_storage_path?: string | null
          fecha_fin?: string
          fecha_inicio?: string
          id?: string
          motivo?: string | null
          persona_id?: string
          registrada_at?: string
          registrada_por?: string
          registrada_tarde?: boolean
          subsidio_diario?: number | null
          tipo?: string
        }
        Relationships: [
          {
            foreignKeyName: "ausencias_anulada_por_fkey"
            columns: ["anulada_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ausencias_anulada_por_fkey"
            columns: ["anulada_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ausencias_aprobada_por_fkey"
            columns: ["aprobada_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ausencias_aprobada_por_fkey"
            columns: ["aprobada_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ausencias_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ausencias_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ausencias_registrada_por_fkey"
            columns: ["registrada_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ausencias_registrada_por_fkey"
            columns: ["registrada_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ausencias_tipo_fkey"
            columns: ["tipo"]
            isOneToOne: false
            referencedRelation: "tipos_ausencia"
            referencedColumns: ["codigo"]
          },
        ]
      }
      bandeja_vistos: {
        Row: {
          item_id: string
          persona_id: string
          tipo_item: string
          visto_at: string
        }
        Insert: {
          item_id: string
          persona_id: string
          tipo_item: string
          visto_at?: string
        }
        Update: {
          item_id?: string
          persona_id?: string
          tipo_item?: string
          visto_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "bandeja_vistos_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bandeja_vistos_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      boletas: {
        Row: {
          anulada_at: string | null
          anulada_motivo: string | null
          anulada_por: string | null
          creada_at: string
          creada_por: string
          estado: string
          id: string
          periodo_id: string
          persona_id: string
          publicada_at: string | null
          publicada_por: string | null
        }
        Insert: {
          anulada_at?: string | null
          anulada_motivo?: string | null
          anulada_por?: string | null
          creada_at?: string
          creada_por: string
          estado?: string
          id?: string
          periodo_id: string
          persona_id: string
          publicada_at?: string | null
          publicada_por?: string | null
        }
        Update: {
          anulada_at?: string | null
          anulada_motivo?: string | null
          anulada_por?: string | null
          creada_at?: string
          creada_por?: string
          estado?: string
          id?: string
          periodo_id?: string
          persona_id?: string
          publicada_at?: string | null
          publicada_por?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "boletas_periodo_id_fkey"
            columns: ["periodo_id"]
            isOneToOne: false
            referencedRelation: "periodos_planilla"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "boletas_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "boletas_creada_por_fkey"
            columns: ["creada_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "boletas_publicada_por_fkey"
            columns: ["publicada_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "boletas_anulada_por_fkey"
            columns: ["anulada_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
        ]
      }
      boletas_acuses: {
        Row: {
          recibida_at: string | null
          version_id: string
          vista_at: string | null
        }
        Insert: {
          recibida_at?: string | null
          version_id: string
          vista_at?: string | null
        }
        Update: {
          recibida_at?: string | null
          version_id?: string
          vista_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "boletas_acuses_version_id_fkey"
            columns: ["version_id"]
            isOneToOne: false
            referencedRelation: "boletas_versiones"
            referencedColumns: ["id"]
          },
        ]
      }
      boletas_partes: {
        Row: {
          bytes: number
          id: string
          mime: string
          orden: number
          storage_path: string
          tipo: string
          version_id: string
        }
        Insert: {
          bytes: number
          id?: string
          mime: string
          orden: number
          storage_path: string
          tipo: string
          version_id: string
        }
        Update: {
          bytes?: number
          id?: string
          mime?: string
          orden?: number
          storage_path?: string
          tipo?: string
          version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "boletas_partes_version_id_tipo_fkey"
            columns: ["version_id"]
            isOneToOne: false
            referencedRelation: "boletas_versiones"
            referencedColumns: ["id"]
          },
        ]
      }
      boletas_versiones: {
        Row: {
          avisar: boolean
          boleta_id: string
          creada_at: string
          creada_por: string
          id: string
          n: number
          nota: string | null
          tipo: string
        }
        Insert: {
          avisar?: boolean
          boleta_id: string
          creada_at?: string
          creada_por: string
          id?: string
          n: number
          nota?: string | null
          tipo: string
        }
        Update: {
          avisar?: boolean
          boleta_id?: string
          creada_at?: string
          creada_por?: string
          id?: string
          n?: number
          nota?: string | null
          tipo?: string
        }
        Relationships: [
          {
            foreignKeyName: "boletas_versiones_boleta_id_fkey"
            columns: ["boleta_id"]
            isOneToOne: false
            referencedRelation: "boletas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "boletas_versiones_creada_por_fkey"
            columns: ["creada_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
        ]
      }
      bonos_umbral_permitido: {
        Row: {
          autorizado_por: string | null
          created_at: string
          id: string
          motivo: string
          persona_id: string
          usado_at: string | null
        }
        Insert: {
          autorizado_por?: string | null
          created_at?: string
          id?: string
          motivo: string
          persona_id: string
          usado_at?: string | null
        }
        Update: {
          autorizado_por?: string | null
          created_at?: string
          id?: string
          motivo?: string
          persona_id?: string
          usado_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "bonos_umbral_permitido_autorizado_por_fkey"
            columns: ["autorizado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bonos_umbral_permitido_autorizado_por_fkey"
            columns: ["autorizado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bonos_umbral_permitido_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bonos_umbral_permitido_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      catalogo_campos_perfil: {
        Row: {
          campo: string
          columnas: string[]
          documento_sugerido: string | null
          etiqueta: string
          requiere_documento: boolean
          solo_do: boolean
        }
        Insert: {
          campo: string
          columnas: string[]
          documento_sugerido?: string | null
          etiqueta: string
          requiere_documento?: boolean
          solo_do?: boolean
        }
        Update: {
          campo?: string
          columnas?: string[]
          documento_sugerido?: string | null
          etiqueta?: string
          requiere_documento?: boolean
          solo_do?: boolean
        }
        Relationships: []
      }
      categorias_laborales: {
        Row: {
          actualizado_at: string
          actualizado_por: string | null
          criterio: string | null
          funciones: string | null
          orden: number
          proposito: string | null
          rango: string
          requisitos: string | null
          salario_declarado: number | null
        }
        Insert: {
          actualizado_at?: string
          actualizado_por?: string | null
          criterio?: string | null
          funciones?: string | null
          orden: number
          proposito?: string | null
          rango: string
          requisitos?: string | null
          salario_declarado?: number | null
        }
        Update: {
          actualizado_at?: string
          actualizado_por?: string | null
          criterio?: string | null
          funciones?: string | null
          orden?: number
          proposito?: string | null
          rango?: string
          requisitos?: string | null
          salario_declarado?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "categorias_laborales_actualizado_por_fkey"
            columns: ["actualizado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "categorias_laborales_actualizado_por_fkey"
            columns: ["actualizado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      configuracion: {
        Row: {
          clave: string
          descripcion: string | null
          valor: Json
        }
        Insert: {
          clave: string
          descripcion?: string | null
          valor: Json
        }
        Update: {
          clave?: string
          descripcion?: string | null
          valor?: Json
        }
        Relationships: []
      }
      confirmaciones_firma_contrato: {
        Row: {
          confirmada_at: string
          contrato_id: string
          id: string
          imagen: string
          persona_id: string
        }
        Insert: {
          confirmada_at?: string
          contrato_id: string
          id?: string
          imagen: string
          persona_id: string
        }
        Update: {
          confirmada_at?: string
          contrato_id?: string
          id?: string
          imagen?: string
          persona_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "confirmaciones_firma_contrato_contrato_id_fkey"
            columns: ["contrato_id"]
            isOneToOne: false
            referencedRelation: "contratos_generados"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "confirmaciones_firma_contrato_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "confirmaciones_firma_contrato_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      consentimientos_datos_personales: {
        Row: {
          aceptado_at: string
          finalidad: string
          id: string
          persona_id: string
          texto: string
        }
        Insert: {
          aceptado_at?: string
          finalidad: string
          id?: string
          persona_id: string
          texto: string
        }
        Update: {
          aceptado_at?: string
          finalidad?: string
          id?: string
          persona_id?: string
          texto?: string
        }
        Relationships: [
          {
            foreignKeyName: "consentimientos_datos_personales_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "consentimientos_datos_personales_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      contrato_revisiones_pedidas: {
        Row: {
          atendida_at: string | null
          atendida_por: string | null
          id: string
          motivo: string
          pedida_at: string
          persona_id: string
          respuesta: string | null
        }
        Insert: {
          atendida_at?: string | null
          atendida_por?: string | null
          id?: string
          motivo: string
          pedida_at?: string
          persona_id: string
          respuesta?: string | null
        }
        Update: {
          atendida_at?: string | null
          atendida_por?: string | null
          id?: string
          motivo?: string
          pedida_at?: string
          persona_id?: string
          respuesta?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "contrato_revisiones_pedidas_atendida_por_fkey"
            columns: ["atendida_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contrato_revisiones_pedidas_atendida_por_fkey"
            columns: ["atendida_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contrato_revisiones_pedidas_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contrato_revisiones_pedidas_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      contratos_generados: {
        Row: {
          anulado_at: string | null
          anulado_motivo: string | null
          anulado_por: string | null
          cargo: string
          comunicado_mtpe_at: string | null
          copia_entregada_at: string | null
          datos_formulario: Json | null
          documento_html: string
          editado_at: string | null
          editado_por: string | null
          fecha_fin: string | null
          fecha_firma: string | null
          fecha_inicio: string
          firma_persona: string | null
          firma_persona_confirmada_at: string | null
          generado_at: string
          generado_por: string
          horas_semanales: number | null
          id: string
          persona_id: string
          registrado_por: string | null
          remuneracion_mensual: number
          sede_id: string
          storage_path: string | null
          tipo: string
        }
        Insert: {
          anulado_at?: string | null
          anulado_motivo?: string | null
          anulado_por?: string | null
          cargo: string
          comunicado_mtpe_at?: string | null
          copia_entregada_at?: string | null
          datos_formulario?: Json | null
          documento_html: string
          editado_at?: string | null
          editado_por?: string | null
          fecha_fin?: string | null
          fecha_firma?: string | null
          fecha_inicio: string
          firma_persona?: string | null
          firma_persona_confirmada_at?: string | null
          generado_at?: string
          generado_por: string
          horas_semanales?: number | null
          id?: string
          persona_id: string
          registrado_por?: string | null
          remuneracion_mensual: number
          sede_id: string
          storage_path?: string | null
          tipo: string
        }
        Update: {
          anulado_at?: string | null
          anulado_motivo?: string | null
          anulado_por?: string | null
          cargo?: string
          comunicado_mtpe_at?: string | null
          copia_entregada_at?: string | null
          datos_formulario?: Json | null
          documento_html?: string
          editado_at?: string | null
          editado_por?: string | null
          fecha_fin?: string | null
          fecha_firma?: string | null
          fecha_inicio?: string
          firma_persona?: string | null
          firma_persona_confirmada_at?: string | null
          generado_at?: string
          generado_por?: string
          horas_semanales?: number | null
          id?: string
          persona_id?: string
          registrado_por?: string | null
          remuneracion_mensual?: number
          sede_id?: string
          storage_path?: string | null
          tipo?: string
        }
        Relationships: [
          {
            foreignKeyName: "contratos_generados_anulado_por_fkey"
            columns: ["anulado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contratos_generados_anulado_por_fkey"
            columns: ["anulado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contratos_generados_editado_por_fkey"
            columns: ["editado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contratos_generados_editado_por_fkey"
            columns: ["editado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contratos_generados_generado_por_fkey"
            columns: ["generado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contratos_generados_generado_por_fkey"
            columns: ["generado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contratos_generados_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contratos_generados_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contratos_generados_registrado_por_fkey"
            columns: ["registrado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contratos_generados_registrado_por_fkey"
            columns: ["registrado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contratos_generados_sede_id_fkey"
            columns: ["sede_id"]
            isOneToOne: false
            referencedRelation: "sedes"
            referencedColumns: ["id"]
          },
        ]
      }
      correcciones_auditoria: {
        Row: {
          campo_modificado: string
          corregido_at: string
          corregido_por: string
          id: string
          marcaje_id: string | null
          motivo: string
          persona_id: string
          valor_anterior: string | null
          valor_nuevo: string | null
        }
        Insert: {
          campo_modificado: string
          corregido_at?: string
          corregido_por: string
          id?: string
          marcaje_id?: string | null
          motivo: string
          persona_id: string
          valor_anterior?: string | null
          valor_nuevo?: string | null
        }
        Update: {
          campo_modificado?: string
          corregido_at?: string
          corregido_por?: string
          id?: string
          marcaje_id?: string | null
          motivo?: string
          persona_id?: string
          valor_anterior?: string | null
          valor_nuevo?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "correcciones_auditoria_corregido_por_fkey"
            columns: ["corregido_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "correcciones_auditoria_corregido_por_fkey"
            columns: ["corregido_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "correcciones_auditoria_marcaje_id_fkey"
            columns: ["marcaje_id"]
            isOneToOne: false
            referencedRelation: "marcajes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "correcciones_auditoria_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "correcciones_auditoria_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      datos_personales: {
        Row: {
          actualizado_at: string
          actualizado_por: string | null
          celular: string | null
          cuspp: string | null
          direccion: string | null
          discapacidad: boolean | null
          discapacidad_conadis: string | null
          emergencia_nombre: string | null
          emergencia_telefono: string | null
          emergencia_vinculo: string | null
          entidad_bancaria: string | null
          estado_civil: string | null
          fecha_nacimiento: string | null
          foto_dni_anverso_ruta: string | null
          foto_dni_reverso_ruta: string | null
          foto_dni_url: string | null
          foto_personal_url: string | null
          foto_profesional_url: string | null
          genero: string | null
          grado_instruccion: string | null
          hijos_menores: boolean | null
          nombre_dni: string | null
          numero_cuenta: string | null
          persona_id: string
        }
        Insert: {
          actualizado_at?: string
          actualizado_por?: string | null
          celular?: string | null
          cuspp?: string | null
          direccion?: string | null
          discapacidad?: boolean | null
          discapacidad_conadis?: string | null
          emergencia_nombre?: string | null
          emergencia_telefono?: string | null
          emergencia_vinculo?: string | null
          entidad_bancaria?: string | null
          estado_civil?: string | null
          fecha_nacimiento?: string | null
          foto_dni_anverso_ruta?: string | null
          foto_dni_reverso_ruta?: string | null
          foto_dni_url?: string | null
          foto_personal_url?: string | null
          foto_profesional_url?: string | null
          genero?: string | null
          grado_instruccion?: string | null
          hijos_menores?: boolean | null
          nombre_dni?: string | null
          numero_cuenta?: string | null
          persona_id: string
        }
        Update: {
          actualizado_at?: string
          actualizado_por?: string | null
          celular?: string | null
          cuspp?: string | null
          direccion?: string | null
          discapacidad?: boolean | null
          discapacidad_conadis?: string | null
          emergencia_nombre?: string | null
          emergencia_telefono?: string | null
          emergencia_vinculo?: string | null
          entidad_bancaria?: string | null
          estado_civil?: string | null
          fecha_nacimiento?: string | null
          foto_dni_anverso_ruta?: string | null
          foto_dni_reverso_ruta?: string | null
          foto_dni_url?: string | null
          foto_personal_url?: string | null
          foto_profesional_url?: string | null
          genero?: string | null
          grado_instruccion?: string | null
          hijos_menores?: boolean | null
          nombre_dni?: string | null
          numero_cuenta?: string | null
          persona_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "datos_personales_actualizado_por_fkey"
            columns: ["actualizado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "datos_personales_actualizado_por_fkey"
            columns: ["actualizado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "datos_personales_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: true
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "datos_personales_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: true
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      derechohabientes: {
        Row: {
          apellidos: string
          created_at: string
          documento: string | null
          essalud: boolean
          fecha_nacimiento: string | null
          id: string
          nombres: string
          nota: string | null
          persona_id: string
          registrado_por: string | null
          vida_ley: boolean
          vigente_hasta: string | null
          vinculo: string
        }
        Insert: {
          apellidos: string
          created_at?: string
          documento?: string | null
          essalud?: boolean
          fecha_nacimiento?: string | null
          id?: string
          nombres: string
          nota?: string | null
          persona_id: string
          registrado_por?: string | null
          vida_ley?: boolean
          vigente_hasta?: string | null
          vinculo: string
        }
        Update: {
          apellidos?: string
          created_at?: string
          documento?: string | null
          essalud?: boolean
          fecha_nacimiento?: string | null
          id?: string
          nombres?: string
          nota?: string | null
          persona_id?: string
          registrado_por?: string | null
          vida_ley?: boolean
          vigente_hasta?: string | null
          vinculo?: string
        }
        Relationships: [
          {
            foreignKeyName: "derechohabientes_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "derechohabientes_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "derechohabientes_registrado_por_fkey"
            columns: ["registrado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "derechohabientes_registrado_por_fkey"
            columns: ["registrado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      desembolsos_beneficios: {
        Row: {
          anio: number
          created_at: string
          fecha_pago: string
          id: string
          monto: number
          nota: string | null
          origen: string
          persona_id: string
          registrado_por: string | null
          ventana: string
        }
        Insert: {
          anio: number
          created_at?: string
          fecha_pago: string
          id?: string
          monto: number
          nota?: string | null
          origen: string
          persona_id: string
          registrado_por?: string | null
          ventana: string
        }
        Update: {
          anio?: number
          created_at?: string
          fecha_pago?: string
          id?: string
          monto?: number
          nota?: string | null
          origen?: string
          persona_id?: string
          registrado_por?: string | null
          ventana?: string
        }
        Relationships: [
          {
            foreignKeyName: "desembolsos_beneficios_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "desembolsos_beneficios_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "desembolsos_beneficios_registrado_por_fkey"
            columns: ["registrado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "desembolsos_beneficios_registrado_por_fkey"
            columns: ["registrado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      documentos_acuses: {
        Row: {
          acusado_at: string
          documento_id: string
          nombre_declarado: string | null
          nota: string | null
          persona_id: string
          registrado_por: string | null
          storage_path: string | null
          via: string
        }
        Insert: {
          acusado_at?: string
          documento_id: string
          nombre_declarado?: string | null
          nota?: string | null
          persona_id: string
          registrado_por?: string | null
          storage_path?: string | null
          via: string
        }
        Update: {
          acusado_at?: string
          documento_id?: string
          nombre_declarado?: string | null
          nota?: string | null
          persona_id?: string
          registrado_por?: string | null
          storage_path?: string | null
          via?: string
        }
        Relationships: [
          {
            foreignKeyName: "documentos_acuses_documento_id_fkey"
            columns: ["documento_id"]
            isOneToOne: false
            referencedRelation: "documentos_institucionales"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "documentos_acuses_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "documentos_acuses_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "documentos_acuses_registrado_por_fkey"
            columns: ["registrado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "documentos_acuses_registrado_por_fkey"
            columns: ["registrado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      documentos_firmados: {
        Row: {
          alcance: string
          anio: number | null
          anulado_at: string | null
          anulado_motivo: string | null
          anulado_por: string | null
          created_at: string
          entrega_confirmada_at: string | null
          entrega_confirmada_el: string | null
          entrega_confirmada_por: string | null
          es_negativa: boolean
          fecha_firma: string
          firma_persona: string | null
          firma_persona_confirmada_at: string | null
          firma_persona_ip: string | null
          firma_persona_user_agent: string | null
          id: string
          monto_declarado: number | null
          movimiento_id: string | null
          nota: string | null
          persona_id: string | null
          registrado_por: string
          ruta_costo_pasaje: number | null
          ruta_costo_taxi: number | null
          ruta_declarada: string | null
          ruta_distrito: string | null
          ruta_frecuencia_taxi: number | null
          ruta_gasto_diario: number | null
          ruta_medios_ida: number | null
          ruta_medios_vuelta: number | null
          ruta_provincia: string | null
          storage_path: string | null
          tipo: string
        }
        Insert: {
          alcance: string
          anio?: number | null
          anulado_at?: string | null
          anulado_motivo?: string | null
          anulado_por?: string | null
          created_at?: string
          entrega_confirmada_at?: string | null
          entrega_confirmada_el?: string | null
          entrega_confirmada_por?: string | null
          es_negativa?: boolean
          fecha_firma: string
          firma_persona?: string | null
          firma_persona_confirmada_at?: string | null
          firma_persona_ip?: string | null
          firma_persona_user_agent?: string | null
          id?: string
          monto_declarado?: number | null
          movimiento_id?: string | null
          nota?: string | null
          persona_id?: string | null
          registrado_por: string
          ruta_costo_pasaje?: number | null
          ruta_costo_taxi?: number | null
          ruta_declarada?: string | null
          ruta_distrito?: string | null
          ruta_frecuencia_taxi?: number | null
          ruta_gasto_diario?: number | null
          ruta_medios_ida?: number | null
          ruta_medios_vuelta?: number | null
          ruta_provincia?: string | null
          storage_path?: string | null
          tipo: string
        }
        Update: {
          alcance?: string
          anio?: number | null
          anulado_at?: string | null
          anulado_motivo?: string | null
          anulado_por?: string | null
          created_at?: string
          entrega_confirmada_at?: string | null
          entrega_confirmada_el?: string | null
          entrega_confirmada_por?: string | null
          es_negativa?: boolean
          fecha_firma?: string
          firma_persona?: string | null
          firma_persona_confirmada_at?: string | null
          firma_persona_ip?: string | null
          firma_persona_user_agent?: string | null
          id?: string
          monto_declarado?: number | null
          movimiento_id?: string | null
          nota?: string | null
          persona_id?: string | null
          registrado_por?: string
          ruta_costo_pasaje?: number | null
          ruta_costo_taxi?: number | null
          ruta_declarada?: string | null
          ruta_distrito?: string | null
          ruta_frecuencia_taxi?: number | null
          ruta_gasto_diario?: number | null
          ruta_medios_ida?: number | null
          ruta_medios_vuelta?: number | null
          ruta_provincia?: string | null
          storage_path?: string | null
          tipo?: string
        }
        Relationships: [
          {
            foreignKeyName: "documentos_firmados_anulado_por_fkey"
            columns: ["anulado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "documentos_firmados_anulado_por_fkey"
            columns: ["anulado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "documentos_firmados_movimiento_id_fkey"
            columns: ["movimiento_id"]
            isOneToOne: false
            referencedRelation: "movimientos_planilla"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "documentos_firmados_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "documentos_firmados_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "documentos_firmados_registrado_por_fkey"
            columns: ["registrado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "documentos_firmados_registrado_por_fkey"
            columns: ["registrado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      documentos_institucionales: {
        Row: {
          documento: string
          etiqueta_version: string | null
          id: string
          notas: string | null
          publicado_at: string
          publicado_por: string | null
          tipo: string
          titulo: string
          version: number
          vigente_desde: string
        }
        Insert: {
          documento: string
          etiqueta_version?: string | null
          id?: string
          notas?: string | null
          publicado_at?: string
          publicado_por?: string | null
          tipo: string
          titulo: string
          version: number
          vigente_desde: string
        }
        Update: {
          documento?: string
          etiqueta_version?: string | null
          id?: string
          notas?: string | null
          publicado_at?: string
          publicado_por?: string | null
          tipo?: string
          titulo?: string
          version?: number
          vigente_desde?: string
        }
        Relationships: [
          {
            foreignKeyName: "documentos_institucionales_publicado_por_fkey"
            columns: ["publicado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "documentos_institucionales_publicado_por_fkey"
            columns: ["publicado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "documentos_institucionales_tipo_fkey"
            columns: ["tipo"]
            isOneToOne: false
            referencedRelation: "documentos_tipos"
            referencedColumns: ["codigo"]
          },
        ]
      }
      documentos_tipos: {
        Row: {
          activo: boolean
          codigo: string
          nombre: string
          orden: number
          requiere_acuse: boolean
        }
        Insert: {
          activo?: boolean
          codigo: string
          nombre: string
          orden?: number
          requiere_acuse?: boolean
        }
        Update: {
          activo?: boolean
          codigo?: string
          nombre?: string
          orden?: number
          requiere_acuse?: boolean
        }
        Relationships: []
      }
      educacion_avisos_fin: {
        Row: {
          asignacion_id: string
          atendido_at: string | null
          atendido_por: string | null
          creado_at: string
          creado_por: string
          id: string
          motivo: string
          respuesta: string | null
          ultimo_pago: string | null
        }
        Insert: {
          asignacion_id: string
          atendido_at?: string | null
          atendido_por?: string | null
          creado_at?: string
          creado_por: string
          id?: string
          motivo: string
          respuesta?: string | null
          ultimo_pago?: string | null
        }
        Update: {
          asignacion_id?: string
          atendido_at?: string | null
          atendido_por?: string | null
          creado_at?: string
          creado_por?: string
          id?: string
          motivo?: string
          respuesta?: string | null
          ultimo_pago?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "educacion_avisos_fin_asignacion_id_fkey"
            columns: ["asignacion_id"]
            isOneToOne: false
            referencedRelation: "asignaciones_educacion"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "educacion_avisos_fin_atendido_por_fkey"
            columns: ["atendido_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "educacion_avisos_fin_atendido_por_fkey"
            columns: ["atendido_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "educacion_avisos_fin_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "educacion_avisos_fin_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      educacion_comprobantes: {
        Row: {
          asignacion_id: string
          created_at: string
          id: string
          mes_cubierto: string
          nota: string | null
          storage_path: string
          subido_por: string | null
        }
        Insert: {
          asignacion_id: string
          created_at?: string
          id?: string
          mes_cubierto: string
          nota?: string | null
          storage_path: string
          subido_por?: string | null
        }
        Update: {
          asignacion_id?: string
          created_at?: string
          id?: string
          mes_cubierto?: string
          nota?: string | null
          storage_path?: string
          subido_por?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "educacion_comprobantes_asignacion_id_fkey"
            columns: ["asignacion_id"]
            isOneToOne: false
            referencedRelation: "asignaciones_educacion"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "educacion_comprobantes_subido_por_fkey"
            columns: ["subido_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "educacion_comprobantes_subido_por_fkey"
            columns: ["subido_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      educacion_entrega_archivos: {
        Row: {
          bytes: number | null
          created_at: string
          entrega_id: string
          id: string
          nombre: string
          orden: number
          storage_path: string
          tipo_mime: string | null
        }
        Insert: {
          bytes?: number | null
          created_at?: string
          entrega_id: string
          id?: string
          nombre: string
          orden: number
          storage_path: string
          tipo_mime?: string | null
        }
        Update: {
          bytes?: number | null
          created_at?: string
          entrega_id?: string
          id?: string
          nombre?: string
          orden?: number
          storage_path?: string
          tipo_mime?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "educacion_entrega_archivos_entrega_id_fkey"
            columns: ["entrega_id"]
            isOneToOne: false
            referencedRelation: "educacion_entregas"
            referencedColumns: ["id"]
          },
        ]
      }
      educacion_entregas: {
        Row: {
          asignacion_id: string
          enviada_at: string
          enviada_por: string | null
          estado: string
          fecha_pago: string
          id: string
          motivo_categoria: string | null
          motivo_comentario: string | null
          nota: string | null
          origen: string
          proxima_fecha_pago: string | null
          reemplaza_a: string | null
          retirada_at: string | null
          revisada_at: string | null
          revisada_por: string | null
          tipo: string
        }
        Insert: {
          asignacion_id: string
          enviada_at?: string
          enviada_por?: string | null
          estado?: string
          fecha_pago: string
          id?: string
          motivo_categoria?: string | null
          motivo_comentario?: string | null
          nota?: string | null
          origen?: string
          proxima_fecha_pago?: string | null
          reemplaza_a?: string | null
          retirada_at?: string | null
          revisada_at?: string | null
          revisada_por?: string | null
          tipo: string
        }
        Update: {
          asignacion_id?: string
          enviada_at?: string
          enviada_por?: string | null
          estado?: string
          fecha_pago?: string
          id?: string
          motivo_categoria?: string | null
          motivo_comentario?: string | null
          nota?: string | null
          origen?: string
          proxima_fecha_pago?: string | null
          reemplaza_a?: string | null
          retirada_at?: string | null
          revisada_at?: string | null
          revisada_por?: string | null
          tipo?: string
        }
        Relationships: [
          {
            foreignKeyName: "educacion_entregas_asignacion_id_fkey"
            columns: ["asignacion_id"]
            isOneToOne: false
            referencedRelation: "asignaciones_educacion"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "educacion_entregas_enviada_por_fkey"
            columns: ["enviada_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "educacion_entregas_enviada_por_fkey"
            columns: ["enviada_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "educacion_entregas_reemplaza_a_fkey"
            columns: ["reemplaza_a"]
            isOneToOne: false
            referencedRelation: "educacion_entregas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "educacion_entregas_revisada_por_fkey"
            columns: ["revisada_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "educacion_entregas_revisada_por_fkey"
            columns: ["revisada_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      educacion_solicitudes: {
        Row: {
          asignacion_id: string | null
          beneficiario: string
          beneficiario_nombre: string | null
          comprobante_url: string | null
          costo_declarado: number
          enviada_at: string
          estado: string
          id: string
          institucion: string
          motivo_rechazo: string | null
          nota: string | null
          persona_id: string
          retirada_at: string | null
          revisada_at: string | null
          revisada_por: string | null
          vigente_desde: string
          vigente_hasta: string
        }
        Insert: {
          asignacion_id?: string | null
          beneficiario: string
          beneficiario_nombre?: string | null
          comprobante_url?: string | null
          costo_declarado: number
          enviada_at?: string
          estado?: string
          id?: string
          institucion: string
          motivo_rechazo?: string | null
          nota?: string | null
          persona_id: string
          retirada_at?: string | null
          revisada_at?: string | null
          revisada_por?: string | null
          vigente_desde: string
          vigente_hasta: string
        }
        Update: {
          asignacion_id?: string | null
          beneficiario?: string
          beneficiario_nombre?: string | null
          comprobante_url?: string | null
          costo_declarado?: number
          enviada_at?: string
          estado?: string
          id?: string
          institucion?: string
          motivo_rechazo?: string | null
          nota?: string | null
          persona_id?: string
          retirada_at?: string | null
          revisada_at?: string | null
          revisada_por?: string | null
          vigente_desde?: string
          vigente_hasta?: string
        }
        Relationships: [
          {
            foreignKeyName: "educacion_solicitudes_asignacion_id_fkey"
            columns: ["asignacion_id"]
            isOneToOne: false
            referencedRelation: "asignaciones_educacion"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "educacion_solicitudes_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "educacion_solicitudes_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "educacion_solicitudes_revisada_por_fkey"
            columns: ["revisada_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "educacion_solicitudes_revisada_por_fkey"
            columns: ["revisada_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      etiquetas_complemento: {
        Row: {
          activa: boolean
          codigo: string
          created_at: string
          etiqueta: string
          nota: string | null
          orden: number
        }
        Insert: {
          activa?: boolean
          codigo: string
          created_at?: string
          etiqueta: string
          nota?: string | null
          orden?: number
        }
        Update: {
          activa?: boolean
          codigo?: string
          created_at?: string
          etiqueta?: string
          nota?: string | null
          orden?: number
        }
        Relationships: []
      }
      expediente_adjuntos: {
        Row: {
          documento_id: string
          id: string
          nota: string | null
          storage_path: string
          subido_at: string
          subido_por: string
          tipo: string
        }
        Insert: {
          documento_id: string
          id?: string
          nota?: string | null
          storage_path: string
          subido_at?: string
          subido_por: string
          tipo?: string
        }
        Update: {
          documento_id?: string
          id?: string
          nota?: string | null
          storage_path?: string
          subido_at?: string
          subido_por?: string
          tipo?: string
        }
        Relationships: [
          {
            foreignKeyName: "expediente_adjuntos_documento_id_fkey"
            columns: ["documento_id"]
            isOneToOne: false
            referencedRelation: "expediente_disciplinario"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expediente_adjuntos_subido_por_fkey"
            columns: ["subido_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expediente_adjuntos_subido_por_fkey"
            columns: ["subido_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      expediente_correlativo_seq: {
        Row: {
          anio: number
          prefijo: string
          ultimo: number
        }
        Insert: {
          anio: number
          prefijo: string
          ultimo?: number
        }
        Update: {
          anio?: number
          prefijo?: string
          ultimo?: number
        }
        Relationships: []
      }
      expediente_disciplinario: {
        Row: {
          cargos_comunicados_at: string | null
          conocido_el: string | null
          correlativo: string | null
          creado_at: string
          creado_por: string
          descargo_acogido: string | null
          descargo_valoracion: string | null
          descargo_vence_at: string | null
          doc_previo_id: string | null
          entrega_testigo_id: string | null
          entrega_testigo_nombre: string | null
          entregado_at: string | null
          entregado_por: string | null
          enviado_a_info_at: string | null
          enviado_a_info_por: string | null
          estado: string
          falta_literal: string | null
          falta_numeral: string | null
          falta_rit_version: number | null
          fecha_cese: string | null
          firma_sancionado: string | null
          firma_sancionado_confirmada_at: string | null
          firmado_at: string | null
          firmante_id: string | null
          hechos: Json
          id: string
          medio_entrega: string | null
          nivel: string
          observacion: string | null
          periodo_desde: string | null
          periodo_hasta: string | null
          persona_id: string
          resuelto_at: string | null
          resuelto_motivo: string | null
          resuelto_por: string | null
          resuelto_resultado: string | null
          sancionado_rechazo_firma_at: string | null
          suspension_desde: string | null
          suspension_dias: number | null
          suspension_fechas: string[] | null
          suspension_hasta: string | null
          tipo_causal: string
          tomado_at: string | null
          tomado_por: string | null
        }
        Insert: {
          cargos_comunicados_at?: string | null
          conocido_el?: string | null
          correlativo?: string | null
          creado_at?: string
          creado_por: string
          descargo_acogido?: string | null
          descargo_valoracion?: string | null
          descargo_vence_at?: string | null
          doc_previo_id?: string | null
          entrega_testigo_id?: string | null
          entrega_testigo_nombre?: string | null
          entregado_at?: string | null
          entregado_por?: string | null
          enviado_a_info_at?: string | null
          enviado_a_info_por?: string | null
          estado?: string
          falta_literal?: string | null
          falta_numeral?: string | null
          falta_rit_version?: number | null
          fecha_cese?: string | null
          firma_sancionado?: string | null
          firma_sancionado_confirmada_at?: string | null
          firmado_at?: string | null
          firmante_id?: string | null
          hechos?: Json
          id?: string
          medio_entrega?: string | null
          nivel: string
          observacion?: string | null
          periodo_desde?: string | null
          periodo_hasta?: string | null
          persona_id: string
          resuelto_at?: string | null
          resuelto_motivo?: string | null
          resuelto_por?: string | null
          resuelto_resultado?: string | null
          sancionado_rechazo_firma_at?: string | null
          suspension_desde?: string | null
          suspension_dias?: number | null
          suspension_fechas?: string[] | null
          suspension_hasta?: string | null
          tipo_causal: string
          tomado_at?: string | null
          tomado_por?: string | null
        }
        Update: {
          cargos_comunicados_at?: string | null
          conocido_el?: string | null
          correlativo?: string | null
          creado_at?: string
          creado_por?: string
          descargo_acogido?: string | null
          descargo_valoracion?: string | null
          descargo_vence_at?: string | null
          doc_previo_id?: string | null
          entrega_testigo_id?: string | null
          entrega_testigo_nombre?: string | null
          entregado_at?: string | null
          entregado_por?: string | null
          enviado_a_info_at?: string | null
          enviado_a_info_por?: string | null
          estado?: string
          falta_literal?: string | null
          falta_numeral?: string | null
          falta_rit_version?: number | null
          fecha_cese?: string | null
          firma_sancionado?: string | null
          firma_sancionado_confirmada_at?: string | null
          firmado_at?: string | null
          firmante_id?: string | null
          hechos?: Json
          id?: string
          medio_entrega?: string | null
          nivel?: string
          observacion?: string | null
          periodo_desde?: string | null
          periodo_hasta?: string | null
          persona_id?: string
          resuelto_at?: string | null
          resuelto_motivo?: string | null
          resuelto_por?: string | null
          resuelto_resultado?: string | null
          sancionado_rechazo_firma_at?: string | null
          suspension_desde?: string | null
          suspension_dias?: number | null
          suspension_fechas?: string[] | null
          suspension_hasta?: string | null
          tipo_causal?: string
          tomado_at?: string | null
          tomado_por?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "expediente_disciplinario_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expediente_disciplinario_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expediente_disciplinario_doc_previo_id_fkey"
            columns: ["doc_previo_id"]
            isOneToOne: false
            referencedRelation: "expediente_disciplinario"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expediente_disciplinario_entrega_testigo_id_fkey"
            columns: ["entrega_testigo_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expediente_disciplinario_entrega_testigo_id_fkey"
            columns: ["entrega_testigo_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expediente_disciplinario_entregado_por_fkey"
            columns: ["entregado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expediente_disciplinario_entregado_por_fkey"
            columns: ["entregado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expediente_disciplinario_enviado_a_info_por_fkey"
            columns: ["enviado_a_info_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expediente_disciplinario_enviado_a_info_por_fkey"
            columns: ["enviado_a_info_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expediente_disciplinario_firmante_id_fkey"
            columns: ["firmante_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expediente_disciplinario_firmante_id_fkey"
            columns: ["firmante_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expediente_disciplinario_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expediente_disciplinario_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expediente_disciplinario_resuelto_por_fkey"
            columns: ["resuelto_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expediente_disciplinario_resuelto_por_fkey"
            columns: ["resuelto_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      expediente_traspasos: {
        Row: {
          accion: string
          expediente_id: string
          hecho_at: string
          id: string
          motivo: string
          por: string
        }
        Insert: {
          accion: string
          expediente_id: string
          hecho_at?: string
          id?: string
          motivo: string
          por: string
        }
        Update: {
          accion?: string
          expediente_id?: string
          hecho_at?: string
          id?: string
          motivo?: string
          por?: string
        }
        Relationships: [
          {
            foreignKeyName: "expediente_traspasos_expediente_id_fkey"
            columns: ["expediente_id"]
            isOneToOne: false
            referencedRelation: "expediente_disciplinario"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expediente_traspasos_por_fkey"
            columns: ["por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
        ]
      }
      factores_categoria: {
        Row: {
          factor: string
          factor_orden: number
          nivel: string
          rango: string
        }
        Insert: {
          factor: string
          factor_orden: number
          nivel: string
          rango: string
        }
        Update: {
          factor?: string
          factor_orden?: number
          nivel?: string
          rango?: string
        }
        Relationships: [
          {
            foreignKeyName: "factores_categoria_rango_fkey"
            columns: ["rango"]
            isOneToOne: false
            referencedRelation: "categorias_laborales"
            referencedColumns: ["rango"]
          },
        ]
      }
      faltas_catalogo: {
        Row: {
          gravedad: string
          literal: string
          numeral: string
          rit_version: number
          se_registra_a_mano: boolean
          texto: string
        }
        Insert: {
          gravedad: string
          literal: string
          numeral: string
          rit_version: number
          se_registra_a_mano: boolean
          texto: string
        }
        Update: {
          gravedad?: string
          literal?: string
          numeral?: string
          rit_version?: number
          se_registra_a_mano?: boolean
          texto?: string
        }
        Relationships: [
        ]
      }
      faltas_rotulos: {
        Row: {
          literal: string
          numeral: string
          rit_version: number
          rotulo: string
        }
        Insert: {
          literal: string
          numeral: string
          rit_version: number
          rotulo: string
        }
        Update: {
          literal?: string
          numeral?: string
          rit_version?: number
          rotulo?: string
        }
        Relationships: [
        ]
      }
      feriados: {
        Row: {
          fecha: string
          nombre: string
        }
        Insert: {
          fecha: string
          nombre: string
        }
        Update: {
          fecha?: string
          nombre?: string
        }
        Relationships: []
      }
      feriados_descanso_sustitutorio: {
        Row: {
          acta_ref: string | null
          created_at: string
          estado: string
          fecha_descanso_sustitutorio: string
          fecha_feriado: string
          id: string
          motivo_fuera_de_plazo: string | null
          otorgado_por: string | null
          persona_id: string
          updated_at: string
        }
        Insert: {
          acta_ref?: string | null
          created_at?: string
          estado?: string
          fecha_descanso_sustitutorio: string
          fecha_feriado: string
          id?: string
          motivo_fuera_de_plazo?: string | null
          otorgado_por?: string | null
          persona_id: string
          updated_at?: string
        }
        Update: {
          acta_ref?: string | null
          created_at?: string
          estado?: string
          fecha_descanso_sustitutorio?: string
          fecha_feriado?: string
          id?: string
          motivo_fuera_de_plazo?: string | null
          otorgado_por?: string | null
          persona_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "feriados_descanso_sustitutorio_fecha_feriado_fkey"
            columns: ["fecha_feriado"]
            isOneToOne: false
            referencedRelation: "feriados"
            referencedColumns: ["fecha"]
          },
          {
            foreignKeyName: "feriados_descanso_sustitutorio_otorgado_por_fkey"
            columns: ["otorgado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feriados_descanso_sustitutorio_otorgado_por_fkey"
            columns: ["otorgado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feriados_descanso_sustitutorio_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feriados_descanso_sustitutorio_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      firmas_escaneadas: {
        Row: {
          actualizado_at: string
          estilo: string | null
          imagen: string
          persona_id: string
          tipo: string
        }
        Insert: {
          actualizado_at?: string
          estilo?: string | null
          imagen: string
          persona_id: string
          tipo?: string
        }
        Update: {
          actualizado_at?: string
          estilo?: string | null
          imagen?: string
          persona_id?: string
          tipo?: string
        }
        Relationships: [
          {
            foreignKeyName: "firmas_escaneadas_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: true
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "firmas_escaneadas_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: true
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      funciones_nunca_para_authenticated: {
        Row: {
          desde: string
          funcion: string
          motivo: string
        }
        Insert: {
          desde?: string
          funcion: string
          motivo: string
        }
        Update: {
          desde?: string
          funcion?: string
          motivo?: string
        }
        Relationships: []
      }
      google_sheets_sync_queue: {
        Row: {
          created_at: string
          estado: string
          id: string
          intentos: number
          jornada_id: string | null
          last_error: string | null
          marcaje_id: string | null
          payload: Json
        }
        Insert: {
          created_at?: string
          estado?: string
          id?: string
          intentos?: number
          jornada_id?: string | null
          last_error?: string | null
          marcaje_id?: string | null
          payload: Json
        }
        Update: {
          created_at?: string
          estado?: string
          id?: string
          intentos?: number
          jornada_id?: string | null
          last_error?: string | null
          marcaje_id?: string | null
          payload?: Json
        }
        Relationships: [
          {
            foreignKeyName: "google_sheets_sync_queue_jornada_id_fkey"
            columns: ["jornada_id"]
            isOneToOne: false
            referencedRelation: "jornadas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "google_sheets_sync_queue_marcaje_id_fkey"
            columns: ["marcaje_id"]
            isOneToOne: false
            referencedRelation: "marcajes"
            referencedColumns: ["id"]
          },
        ]
      }
      horarios_asignados: {
        Row: {
          almuerzo_max_minutos: number
          almuerzo_min_minutos: number
          created_at: string
          dias_laborables: number[]
          hora_entrada: string
          hora_salida: string
          horario_por_dia: Json | null
          horas_semana_objetivo: number
          id: string
          persona_id: string
          vigente_desde: string
          vigente_hasta: string | null
        }
        Insert: {
          almuerzo_max_minutos?: number
          almuerzo_min_minutos?: number
          created_at?: string
          dias_laborables?: number[]
          hora_entrada: string
          hora_salida: string
          horario_por_dia?: Json | null
          horas_semana_objetivo?: number
          id?: string
          persona_id: string
          vigente_desde: string
          vigente_hasta?: string | null
        }
        Update: {
          almuerzo_max_minutos?: number
          almuerzo_min_minutos?: number
          created_at?: string
          dias_laborables?: number[]
          hora_entrada?: string
          hora_salida?: string
          horario_por_dia?: Json | null
          horas_semana_objetivo?: number
          id?: string
          persona_id?: string
          vigente_desde?: string
          vigente_hasta?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "horarios_asignados_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "horarios_asignados_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      incidencias_aceptadas: {
        Row: {
          aceptado_at: string
          aceptado_por: string
          anulada_at: string | null
          anulada_motivo: string | null
          anulada_por: string | null
          fecha: string
          id: string
          nota: string | null
          persona_id: string
          tipo: string
          valor: number | null
        }
        Insert: {
          aceptado_at?: string
          aceptado_por: string
          anulada_at?: string | null
          anulada_motivo?: string | null
          anulada_por?: string | null
          fecha: string
          id?: string
          nota?: string | null
          persona_id: string
          tipo: string
          valor?: number | null
        }
        Update: {
          aceptado_at?: string
          aceptado_por?: string
          anulada_at?: string | null
          anulada_motivo?: string | null
          anulada_por?: string | null
          fecha?: string
          id?: string
          nota?: string | null
          persona_id?: string
          tipo?: string
          valor?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "incidencias_aceptadas_aceptado_por_fkey"
            columns: ["aceptado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "incidencias_aceptadas_aceptado_por_fkey"
            columns: ["aceptado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "incidencias_aceptadas_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "incidencias_aceptadas_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      jornadas: {
        Row: {
          entrada_ts: string | null
          estado: Database["public"]["Enums"]["estado_jornada"]
          fecha: string
          horario_aplicado: Json | null
          horas_extra_detectadas: number
          horas_trabajadas: number | null
          id: string
          minutos_salida_temprana: number | null
          minutos_tarde: number | null
          persona_id: string
          salida_final_ts: string | null
          sede_id: string | null
          tiene_salida_no_retornada: boolean
          updated_at: string
        }
        Insert: {
          entrada_ts?: string | null
          estado?: Database["public"]["Enums"]["estado_jornada"]
          fecha: string
          horario_aplicado?: Json | null
          horas_extra_detectadas?: number
          horas_trabajadas?: number | null
          id?: string
          minutos_salida_temprana?: number | null
          minutos_tarde?: number | null
          persona_id: string
          salida_final_ts?: string | null
          sede_id?: string | null
          tiene_salida_no_retornada?: boolean
          updated_at?: string
        }
        Update: {
          entrada_ts?: string | null
          estado?: Database["public"]["Enums"]["estado_jornada"]
          fecha?: string
          horario_aplicado?: Json | null
          horas_extra_detectadas?: number
          horas_trabajadas?: number | null
          id?: string
          minutos_salida_temprana?: number | null
          minutos_tarde?: number | null
          persona_id?: string
          salida_final_ts?: string | null
          sede_id?: string | null
          tiene_salida_no_retornada?: boolean
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "jornadas_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jornadas_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jornadas_sede_id_fkey"
            columns: ["sede_id"]
            isOneToOne: false
            referencedRelation: "sedes"
            referencedColumns: ["id"]
          },
        ]
      }
      liquidacion_pagada: {
        Row: {
          anula_version: number | null
          anulada: boolean
          congelada_at: string
          congelada_por: string
          detalle: Json
          fecha_cese: string
          fecha_ingreso: string | null
          fecha_pago: string | null
          monto_cts: number
          monto_grati: number
          monto_periodo: number
          monto_vacaciones: number
          motivo_anulacion: string | null
          nota: string | null
          persona: string
          persona_id: string
          total: number
          version: number
        }
        Insert: {
          anula_version?: number | null
          anulada?: boolean
          congelada_at?: string
          congelada_por: string
          detalle: Json
          fecha_cese: string
          fecha_ingreso?: string | null
          fecha_pago?: string | null
          monto_cts?: number
          monto_grati?: number
          monto_periodo?: number
          monto_vacaciones?: number
          motivo_anulacion?: string | null
          nota?: string | null
          persona: string
          persona_id: string
          total: number
          version: number
        }
        Update: {
          anula_version?: number | null
          anulada?: boolean
          congelada_at?: string
          congelada_por?: string
          detalle?: Json
          fecha_cese?: string
          fecha_ingreso?: string | null
          fecha_pago?: string | null
          monto_cts?: number
          monto_grati?: number
          monto_periodo?: number
          monto_vacaciones?: number
          motivo_anulacion?: string | null
          nota?: string | null
          persona?: string
          persona_id?: string
          total?: number
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "liquidacion_pagada_congelada_por_fkey"
            columns: ["congelada_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "liquidacion_pagada_congelada_por_fkey"
            columns: ["congelada_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "liquidacion_pagada_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "liquidacion_pagada_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      marcajes: {
        Row: {
          anulada_at: string | null
          anulada_motivo: string | null
          anulada_por: string | null
          client_uuid: string
          confirmo_sin_refrigerio: boolean | null
          estado_revision: Database["public"]["Enums"]["estado_revision"]
          fecha_jornada: string | null
          id: string
          motivo_otro: string | null
          origen: Database["public"]["Enums"]["origen_marca"]
          persona_id: string
          sede_id: string
          server_received_at: string
          terminal_id: string | null
          timestamp_marca: string
          tipo: Database["public"]["Enums"]["tipo_marca"]
        }
        Insert: {
          anulada_at?: string | null
          anulada_motivo?: string | null
          anulada_por?: string | null
          client_uuid: string
          confirmo_sin_refrigerio?: boolean | null
          estado_revision?: Database["public"]["Enums"]["estado_revision"]
          fecha_jornada?: string | null
          id?: string
          motivo_otro?: string | null
          origen?: Database["public"]["Enums"]["origen_marca"]
          persona_id: string
          sede_id: string
          server_received_at?: string
          terminal_id?: string | null
          timestamp_marca: string
          tipo: Database["public"]["Enums"]["tipo_marca"]
        }
        Update: {
          anulada_at?: string | null
          anulada_motivo?: string | null
          anulada_por?: string | null
          client_uuid?: string
          confirmo_sin_refrigerio?: boolean | null
          estado_revision?: Database["public"]["Enums"]["estado_revision"]
          fecha_jornada?: string | null
          id?: string
          motivo_otro?: string | null
          origen?: Database["public"]["Enums"]["origen_marca"]
          persona_id?: string
          sede_id?: string
          server_received_at?: string
          terminal_id?: string | null
          timestamp_marca?: string
          tipo?: Database["public"]["Enums"]["tipo_marca"]
        }
        Relationships: [
          {
            foreignKeyName: "marcajes_anulada_por_fkey"
            columns: ["anulada_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "marcajes_anulada_por_fkey"
            columns: ["anulada_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "marcajes_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "marcajes_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "marcajes_sede_id_fkey"
            columns: ["sede_id"]
            isOneToOne: false
            referencedRelation: "sedes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "marcajes_terminal_id_fkey"
            columns: ["terminal_id"]
            isOneToOne: false
            referencedRelation: "terminales"
            referencedColumns: ["id"]
          },
        ]
      }
      marcas_apartadas: {
        Row: {
          client_uuid: string
          id: string
          motivo: string | null
          motivo_otro: string | null
          persona_id: string
          reportada_at: string
          resolucion: string | null
          resuelta_at: string | null
          resuelta_por: string | null
          terminal_id: string | null
          timestamp_cliente: string
          tipo: Database["public"]["Enums"]["tipo_marca"]
          ultimo_error: string | null
        }
        Insert: {
          client_uuid: string
          id?: string
          motivo?: string | null
          motivo_otro?: string | null
          persona_id: string
          reportada_at?: string
          resolucion?: string | null
          resuelta_at?: string | null
          resuelta_por?: string | null
          terminal_id?: string | null
          timestamp_cliente: string
          tipo: Database["public"]["Enums"]["tipo_marca"]
          ultimo_error?: string | null
        }
        Update: {
          client_uuid?: string
          id?: string
          motivo?: string | null
          motivo_otro?: string | null
          persona_id?: string
          reportada_at?: string
          resolucion?: string | null
          resuelta_at?: string | null
          resuelta_por?: string | null
          terminal_id?: string | null
          timestamp_cliente?: string
          tipo?: Database["public"]["Enums"]["tipo_marca"]
          ultimo_error?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "marcas_apartadas_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "marcas_apartadas_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "marcas_apartadas_resuelta_por_fkey"
            columns: ["resuelta_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "marcas_apartadas_resuelta_por_fkey"
            columns: ["resuelta_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      mensajes_encargada: {
        Row: {
          creada_at: string
          estado: string
          id: string
          mensaje: string
          persona_id: string
          respondida_at: string | null
          respondida_por: string | null
          respuesta: string | null
          sede_id: string
        }
        Insert: {
          creada_at?: string
          estado?: string
          id?: string
          mensaje: string
          persona_id: string
          respondida_at?: string | null
          respondida_por?: string | null
          respuesta?: string | null
          sede_id: string
        }
        Update: {
          creada_at?: string
          estado?: string
          id?: string
          mensaje?: string
          persona_id?: string
          respondida_at?: string | null
          respondida_por?: string | null
          respuesta?: string | null
          sede_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "mensajes_encargada_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "mensajes_encargada_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "mensajes_encargada_respondida_por_fkey"
            columns: ["respondida_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "mensajes_encargada_respondida_por_fkey"
            columns: ["respondida_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "mensajes_encargada_sede_id_fkey"
            columns: ["sede_id"]
            isOneToOne: false
            referencedRelation: "sedes"
            referencedColumns: ["id"]
          },
        ]
      }
      metas_cobertura: {
        Row: {
          dia_semana: number
          meta: number
          meta_encargadas: number
          meta_tarde: number
          sede_id: string
          updated_at: string
        }
        Insert: {
          dia_semana: number
          meta?: number
          meta_encargadas?: number
          meta_tarde?: number
          sede_id: string
          updated_at?: string
        }
        Update: {
          dia_semana?: number
          meta?: number
          meta_encargadas?: number
          meta_tarde?: number
          sede_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "metas_cobertura_sede_id_fkey"
            columns: ["sede_id"]
            isOneToOne: false
            referencedRelation: "sedes"
            referencedColumns: ["id"]
          },
        ]
      }
      migraciones_aplicadas: {
        Row: {
          aplicada_at: string
          nombre: string
          numero: number
        }
        Insert: {
          aplicada_at?: string
          nombre: string
          numero: number
        }
        Update: {
          aplicada_at?: string
          nombre?: string
          numero?: number
        }
        Relationships: []
      }
      movilidad_revisiones_pedidas: {
        Row: {
          atendida_at: string | null
          atendida_por: string | null
          id: string
          motivo: string
          pedida_at: string
          persona_id: string
          respuesta: string | null
        }
        Insert: {
          atendida_at?: string | null
          atendida_por?: string | null
          id?: string
          motivo: string
          pedida_at?: string
          persona_id: string
          respuesta?: string | null
        }
        Update: {
          atendida_at?: string | null
          atendida_por?: string | null
          id?: string
          motivo?: string
          pedida_at?: string
          persona_id?: string
          respuesta?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "movilidad_revisiones_pedidas_atendida_por_fkey"
            columns: ["atendida_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "movilidad_revisiones_pedidas_atendida_por_fkey"
            columns: ["atendida_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "movilidad_revisiones_pedidas_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "movilidad_revisiones_pedidas_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      movimientos_planilla: {
        Row: {
          categoria: string | null
          concepto: string
          creado_por: string | null
          created_at: string
          id: string
          monto: number
          periodo_id: string
          periodo_origen_id: string | null
          persona_id: string
          tipo: string
        }
        Insert: {
          categoria?: string | null
          concepto: string
          creado_por?: string | null
          created_at?: string
          id?: string
          monto: number
          periodo_id: string
          periodo_origen_id?: string | null
          persona_id: string
          tipo: string
        }
        Update: {
          categoria?: string | null
          concepto?: string
          creado_por?: string | null
          created_at?: string
          id?: string
          monto?: number
          periodo_id?: string
          periodo_origen_id?: string | null
          persona_id?: string
          tipo?: string
        }
        Relationships: [
          {
            foreignKeyName: "movimientos_planilla_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "movimientos_planilla_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "movimientos_planilla_periodo_id_fkey"
            columns: ["periodo_id"]
            isOneToOne: false
            referencedRelation: "periodos_planilla"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "movimientos_planilla_periodo_origen_id_fkey"
            columns: ["periodo_origen_id"]
            isOneToOne: false
            referencedRelation: "periodos_planilla"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "movimientos_planilla_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "movimientos_planilla_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      novedades_vistas: {
        Row: {
          novedad_id: string
          persona_id: string
          visto_at: string
        }
        Insert: {
          novedad_id: string
          persona_id: string
          visto_at?: string
        }
        Update: {
          novedad_id?: string
          persona_id?: string
          visto_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "novedades_vistas_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "novedades_vistas_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      objetivos_items: {
        Row: {
          anio: number
          created_at: string
          cumplido: boolean
          descripcion: string
          id: string
          indicaciones: string | null
          mes: number
          orden: number
          persona_id: string
          updated_at: string
        }
        Insert: {
          anio: number
          created_at?: string
          cumplido?: boolean
          descripcion: string
          id?: string
          indicaciones?: string | null
          mes: number
          orden?: number
          persona_id: string
          updated_at?: string
        }
        Update: {
          anio?: number
          created_at?: string
          cumplido?: boolean
          descripcion?: string
          id?: string
          indicaciones?: string | null
          mes?: number
          orden?: number
          persona_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "objetivos_items_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "objetivos_items_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      objetivos_mensuales: {
        Row: {
          anio: number
          cumplidos: number
          mes: number
          persona_id: string
          total: number
          updated_at: string
        }
        Insert: {
          anio: number
          cumplidos: number
          mes: number
          persona_id: string
          total?: number
          updated_at?: string
        }
        Update: {
          anio?: number
          cumplidos?: number
          mes?: number
          persona_id?: string
          total?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "objetivos_mensuales_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "objetivos_mensuales_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      parametros_laborales: {
        Row: {
          clave: string
          created_at: string
          id: string
          sede_codigo: string | null
          sustento: string | null
          valor: number
          vigente_desde: string
          vigente_hasta: string | null
        }
        Insert: {
          clave: string
          created_at?: string
          id?: string
          sede_codigo?: string | null
          sustento?: string | null
          valor: number
          vigente_desde: string
          vigente_hasta?: string | null
        }
        Update: {
          clave?: string
          created_at?: string
          id?: string
          sede_codigo?: string | null
          sustento?: string | null
          valor?: number
          vigente_desde?: string
          vigente_hasta?: string | null
        }
        Relationships: []
      }
      periodo_grupo_pago: {
        Row: {
          estado: string
          grupo: string
          pagado_at: string | null
          pagado_por: string | null
          periodo_id: string
        }
        Insert: {
          estado?: string
          grupo: string
          pagado_at?: string | null
          pagado_por?: string | null
          periodo_id: string
        }
        Update: {
          estado?: string
          grupo?: string
          pagado_at?: string | null
          pagado_por?: string | null
          periodo_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "periodo_grupo_pago_pagado_por_fkey"
            columns: ["pagado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "periodo_grupo_pago_pagado_por_fkey"
            columns: ["pagado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "periodo_grupo_pago_periodo_id_fkey"
            columns: ["periodo_id"]
            isOneToOne: false
            referencedRelation: "periodos_planilla"
            referencedColumns: ["id"]
          },
        ]
      }
      periodos_planilla: {
        Row: {
          creado_por: string | null
          created_at: string
          estado: string
          fecha_fin: string
          fecha_ini: string
          id: string
          pagado_at: string | null
        }
        Insert: {
          creado_por?: string | null
          created_at?: string
          estado?: string
          fecha_fin: string
          fecha_ini: string
          id?: string
          pagado_at?: string | null
        }
        Update: {
          creado_por?: string | null
          created_at?: string
          estado?: string
          fecha_fin?: string
          fecha_ini?: string
          id?: string
          pagado_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "periodos_planilla_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "periodos_planilla_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      personas: {
        Row: {
          apellidos: string
          auth_user_id: string | null
          cargo: string | null
          cobra_movilidad: boolean
          con_hijos: boolean
          constancia_4ta_hasta: string | null
          created_at: string
          cuenta_de_servicio: boolean
          devenga_beneficios: boolean | null
          devenga_cts: boolean | null
          devenga_grati: boolean | null
          devenga_hasta: string | null
          devenga_vacaciones: boolean | null
          documento: string | null
          email: string | null
          en_planilla: boolean | null
          es_encargada_piso: boolean
          estado: string
          fecha_cese: string | null
          fecha_estado_cambio: string | null
          fecha_fin_contrato: string | null
          fecha_ingreso: string
          foto_url: string | null
          funcion: string
          id: string
          motivo_cese: string | null
          movilidad_motivo: string | null
          nombres: string
          personal_direccion: boolean
          pin_hash: string
          practicante_modalidad: string | null
          regimen_pension: string | null
          retencion_4ta: string | null
          rol: Database["public"]["Enums"]["rol_usuario"]
          sede_base_id: string
          sede_fisica_id: string | null
          sueldo_base_legal: number | null
          sueldo_fijo: boolean
          tipo_documento: string | null
          tipo_vinculo: string
          updated_at: string
          visible_todas_sedes: boolean
        }
        Insert: {
          apellidos: string
          auth_user_id?: string | null
          cargo?: string | null
          cobra_movilidad?: boolean
          con_hijos?: boolean
          constancia_4ta_hasta?: string | null
          created_at?: string
          cuenta_de_servicio?: boolean
          devenga_beneficios?: boolean | null
          devenga_cts?: boolean | null
          devenga_grati?: boolean | null
          devenga_hasta?: string | null
          devenga_vacaciones?: boolean | null
          documento?: string | null
          email?: string | null
          en_planilla?: boolean | null
          es_encargada_piso?: boolean
          estado?: string
          fecha_cese?: string | null
          fecha_estado_cambio?: string | null
          fecha_fin_contrato?: string | null
          fecha_ingreso?: string
          foto_url?: string | null
          funcion?: string
          id?: string
          motivo_cese?: string | null
          movilidad_motivo?: string | null
          nombres: string
          personal_direccion?: boolean
          pin_hash: string
          practicante_modalidad?: string | null
          regimen_pension?: string | null
          retencion_4ta?: string | null
          rol?: Database["public"]["Enums"]["rol_usuario"]
          sede_base_id: string
          sede_fisica_id?: string | null
          sueldo_base_legal?: number | null
          sueldo_fijo?: boolean
          tipo_documento?: string | null
          tipo_vinculo?: string
          updated_at?: string
          visible_todas_sedes?: boolean
        }
        Update: {
          apellidos?: string
          auth_user_id?: string | null
          cargo?: string | null
          cobra_movilidad?: boolean
          con_hijos?: boolean
          constancia_4ta_hasta?: string | null
          created_at?: string
          cuenta_de_servicio?: boolean
          devenga_beneficios?: boolean | null
          devenga_cts?: boolean | null
          devenga_grati?: boolean | null
          devenga_hasta?: string | null
          devenga_vacaciones?: boolean | null
          documento?: string | null
          email?: string | null
          en_planilla?: boolean | null
          es_encargada_piso?: boolean
          estado?: string
          fecha_cese?: string | null
          fecha_estado_cambio?: string | null
          fecha_fin_contrato?: string | null
          fecha_ingreso?: string
          foto_url?: string | null
          funcion?: string
          id?: string
          motivo_cese?: string | null
          movilidad_motivo?: string | null
          nombres?: string
          personal_direccion?: boolean
          pin_hash?: string
          practicante_modalidad?: string | null
          regimen_pension?: string | null
          retencion_4ta?: string | null
          rol?: Database["public"]["Enums"]["rol_usuario"]
          sede_base_id?: string
          sede_fisica_id?: string | null
          sueldo_base_legal?: number | null
          sueldo_fijo?: boolean
          tipo_documento?: string | null
          tipo_vinculo?: string
          updated_at?: string
          visible_todas_sedes?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "personas_funcion_fk"
            columns: ["funcion"]
            isOneToOne: false
            referencedRelation: "areas"
            referencedColumns: ["codigo"]
          },
          {
            foreignKeyName: "personas_sede_base_id_fkey"
            columns: ["sede_base_id"]
            isOneToOne: false
            referencedRelation: "sedes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "personas_sede_fisica_id_fkey"
            columns: ["sede_fisica_id"]
            isOneToOne: false
            referencedRelation: "sedes"
            referencedColumns: ["id"]
          },
        ]
      }
      planilla_pagada_detalle: {
        Row: {
          aporte_essalud: number
          area_codigo: string | null
          asignacion_familiar: number
          bonos: number
          congelada_at: string
          congelada_por: string | null
          costo_total: number | null
          descuento_pension: number
          descuentos: number
          dias_trabajados: number
          fila: Json
          grupo: string
          horas_mes: number
          monto_descanso_semanal: number
          monto_educacion: number
          monto_feriados: number
          monto_movilidad: number
          monto_plus: number
          monto_sobretiempo: number
          nombre: string
          origen: string
          pago_base: number
          periodo_id: string
          persona_id: string
          provision_bonif_extraordinaria: number
          provision_cts: number
          provision_gratificacion: number
          provision_total: number
          provision_vacaciones: number
          rango: string | null
          retencion_4ta: number | null
          salario_ref: number | null
          sede_codigo: string
          total: number
          version: number
        }
        Insert: {
          aporte_essalud?: number
          area_codigo?: string | null
          asignacion_familiar?: number
          bonos?: number
          congelada_at?: string
          congelada_por?: string | null
          costo_total?: number | null
          descuento_pension?: number
          descuentos?: number
          dias_trabajados?: number
          fila: Json
          grupo?: string
          horas_mes?: number
          monto_descanso_semanal?: number
          monto_educacion?: number
          monto_feriados?: number
          monto_movilidad?: number
          monto_plus?: number
          monto_sobretiempo?: number
          nombre: string
          origen: string
          pago_base?: number
          periodo_id: string
          persona_id: string
          provision_bonif_extraordinaria?: number
          provision_cts?: number
          provision_gratificacion?: number
          provision_total?: number
          provision_vacaciones?: number
          rango?: string | null
          retencion_4ta?: number | null
          salario_ref?: number | null
          sede_codigo: string
          total: number
          version: number
        }
        Update: {
          aporte_essalud?: number
          area_codigo?: string | null
          asignacion_familiar?: number
          bonos?: number
          congelada_at?: string
          congelada_por?: string | null
          costo_total?: number | null
          descuento_pension?: number
          descuentos?: number
          dias_trabajados?: number
          fila?: Json
          grupo?: string
          horas_mes?: number
          monto_descanso_semanal?: number
          monto_educacion?: number
          monto_feriados?: number
          monto_movilidad?: number
          monto_plus?: number
          monto_sobretiempo?: number
          nombre?: string
          origen?: string
          pago_base?: number
          periodo_id?: string
          persona_id?: string
          provision_bonif_extraordinaria?: number
          provision_cts?: number
          provision_gratificacion?: number
          provision_total?: number
          provision_vacaciones?: number
          rango?: string | null
          retencion_4ta?: number | null
          salario_ref?: number | null
          sede_codigo?: string
          total?: number
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "planilla_pagada_detalle_congelada_por_fkey"
            columns: ["congelada_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "planilla_pagada_detalle_congelada_por_fkey"
            columns: ["congelada_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "planilla_pagada_detalle_periodo_id_fkey"
            columns: ["periodo_id"]
            isOneToOne: false
            referencedRelation: "periodos_planilla"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "planilla_pagada_detalle_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "planilla_pagada_detalle_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      politica_salarial: {
        Row: {
          documento: string
          huella_cuadro: string
          notas: string | null
          publicada_at: string
          publicada_por: string | null
          version: number
        }
        Insert: {
          documento: string
          huella_cuadro: string
          notas?: string | null
          publicada_at?: string
          publicada_por?: string | null
          version: number
        }
        Update: {
          documento?: string
          huella_cuadro?: string
          notas?: string | null
          publicada_at?: string
          publicada_por?: string | null
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "politica_salarial_publicada_por_fkey"
            columns: ["publicada_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "politica_salarial_publicada_por_fkey"
            columns: ["publicada_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      politica_salarial_acuses: {
        Row: {
          acusado_at: string
          nombre_declarado: string
          persona_id: string
          version: number
        }
        Insert: {
          acusado_at?: string
          nombre_declarado: string
          persona_id: string
          version: number
        }
        Update: {
          acusado_at?: string
          nombre_declarado?: string
          persona_id?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "politica_salarial_acuses_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "politica_salarial_acuses_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "politica_salarial_acuses_version_fkey"
            columns: ["version"]
            isOneToOne: false
            referencedRelation: "politica_salarial"
            referencedColumns: ["version"]
          },
        ]
      }
      push_tokens: {
        Row: {
          activo: boolean
          expo_push_token: string
          id: string
          last_seen_at: string
          persona_id: string
          plataforma: string
        }
        Insert: {
          activo?: boolean
          expo_push_token: string
          id?: string
          last_seen_at?: string
          persona_id: string
          plataforma: string
        }
        Update: {
          activo?: boolean
          expo_push_token?: string
          id?: string
          last_seen_at?: string
          persona_id?: string
          plataforma?: string
        }
        Relationships: [
          {
            foreignKeyName: "push_tokens_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "push_tokens_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      rendimiento_mensual: {
        Row: {
          anio: number
          created_at: string
          etiqueta_codigo: string | null
          mes: number
          nota: string | null
          persona_id: string
          porcentaje: number
          puesto_por: string | null
          updated_at: string
        }
        Insert: {
          anio: number
          created_at?: string
          etiqueta_codigo?: string | null
          mes: number
          nota?: string | null
          persona_id: string
          porcentaje: number
          puesto_por?: string | null
          updated_at?: string
        }
        Update: {
          anio?: number
          created_at?: string
          etiqueta_codigo?: string | null
          mes?: number
          nota?: string | null
          persona_id?: string
          porcentaje?: number
          puesto_por?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "rendimiento_mensual_etiqueta_codigo_fkey"
            columns: ["etiqueta_codigo"]
            isOneToOne: false
            referencedRelation: "etiquetas_complemento"
            referencedColumns: ["codigo"]
          },
          {
            foreignKeyName: "rendimiento_mensual_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rendimiento_mensual_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rendimiento_mensual_puesto_por_fkey"
            columns: ["puesto_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rendimiento_mensual_puesto_por_fkey"
            columns: ["puesto_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      reversas_pago: {
        Row: {
          grupo: string | null
          id: string
          motivo: string
          pagado_at_previo: string | null
          periodo_id: string
          revertido_at: string
          revertido_por: string | null
          tipo: string
        }
        Insert: {
          grupo?: string | null
          id?: string
          motivo: string
          pagado_at_previo?: string | null
          periodo_id: string
          revertido_at?: string
          revertido_por?: string | null
          tipo?: string
        }
        Update: {
          grupo?: string | null
          id?: string
          motivo?: string
          pagado_at_previo?: string | null
          periodo_id?: string
          revertido_at?: string
          revertido_por?: string | null
          tipo?: string
        }
        Relationships: [
          {
            foreignKeyName: "reversas_pago_periodo_id_fkey"
            columns: ["periodo_id"]
            isOneToOne: false
            referencedRelation: "periodos_planilla"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reversas_pago_revertido_por_fkey"
            columns: ["revertido_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reversas_pago_revertido_por_fkey"
            columns: ["revertido_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      revisiones_pedidas: {
        Row: {
          atendida_at: string | null
          atendida_por: string | null
          comentario: string
          fecha: string
          id: string
          pedida_at: string
          persona_id: string
          respuesta: string | null
        }
        Insert: {
          atendida_at?: string | null
          atendida_por?: string | null
          comentario: string
          fecha: string
          id?: string
          pedida_at?: string
          persona_id: string
          respuesta?: string | null
        }
        Update: {
          atendida_at?: string | null
          atendida_por?: string | null
          comentario?: string
          fecha?: string
          id?: string
          pedida_at?: string
          persona_id?: string
          respuesta?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "revisiones_pedidas_atendida_por_fkey"
            columns: ["atendida_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "revisiones_pedidas_atendida_por_fkey"
            columns: ["atendida_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "revisiones_pedidas_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "revisiones_pedidas_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      sedes: {
        Row: {
          activa: boolean
          ciudad: string | null
          codigo: string
          id: string
          nombre: string
          tipo: string
        }
        Insert: {
          activa?: boolean
          ciudad?: string | null
          codigo: string
          id?: string
          nombre: string
          tipo?: string
        }
        Update: {
          activa?: boolean
          ciudad?: string | null
          codigo?: string
          id?: string
          nombre?: string
          tipo?: string
        }
        Relationships: []
      }
      seguimiento_planilla_por_solicitud: {
        Row: {
          campo: string
          creada_at: string
          descripcion: string
          estado: string
          id: string
          nota: string | null
          persona_id: string
          resuelta_at: string | null
          resuelta_por: string | null
          solicitud_id: string
        }
        Insert: {
          campo: string
          creada_at?: string
          descripcion: string
          estado?: string
          id?: string
          nota?: string | null
          persona_id: string
          resuelta_at?: string | null
          resuelta_por?: string | null
          solicitud_id: string
        }
        Update: {
          campo?: string
          creada_at?: string
          descripcion?: string
          estado?: string
          id?: string
          nota?: string | null
          persona_id?: string
          resuelta_at?: string | null
          resuelta_por?: string | null
          solicitud_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "seguimiento_planilla_por_solicitud_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "seguimiento_planilla_por_solicitud_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "seguimiento_planilla_por_solicitud_resuelta_por_fkey"
            columns: ["resuelta_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "seguimiento_planilla_por_solicitud_resuelta_por_fkey"
            columns: ["resuelta_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "seguimiento_planilla_por_solicitud_solicitud_id_fkey"
            columns: ["solicitud_id"]
            isOneToOne: true
            referencedRelation: "solicitudes_cambio_perfil"
            referencedColumns: ["id"]
          },
        ]
      }
      solicitudes_cambio_perfil: {
        Row: {
          campo: string
          creada_at: string
          estado: string
          id: string
          motivo: string | null
          persona_id: string
          resuelta_at: string | null
          resuelta_por: string | null
          rutas_adjuntas: string[]
          valor_anterior: Json
          valor_propuesto: Json
        }
        Insert: {
          campo: string
          creada_at?: string
          estado?: string
          id?: string
          motivo?: string | null
          persona_id: string
          resuelta_at?: string | null
          resuelta_por?: string | null
          rutas_adjuntas?: string[]
          valor_anterior: Json
          valor_propuesto: Json
        }
        Update: {
          campo?: string
          creada_at?: string
          estado?: string
          id?: string
          motivo?: string | null
          persona_id?: string
          resuelta_at?: string | null
          resuelta_por?: string | null
          rutas_adjuntas?: string[]
          valor_anterior?: Json
          valor_propuesto?: Json
        }
        Relationships: [
          {
            foreignKeyName: "solicitudes_cambio_perfil_campo_fkey"
            columns: ["campo"]
            isOneToOne: false
            referencedRelation: "catalogo_campos_perfil"
            referencedColumns: ["campo"]
          },
          {
            foreignKeyName: "solicitudes_cambio_perfil_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "solicitudes_cambio_perfil_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "solicitudes_cambio_perfil_resuelta_por_fkey"
            columns: ["resuelta_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "solicitudes_cambio_perfil_resuelta_por_fkey"
            columns: ["resuelta_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      solicitudes_vacaciones: {
        Row: {
          ausencia_id: string | null
          comentario: string | null
          estado: string
          fecha_fin: string
          fecha_inicio: string
          id: string
          pedida_at: string
          persona_id: string
          respuesta: string | null
          resuelta_at: string | null
          resuelta_por: string | null
        }
        Insert: {
          ausencia_id?: string | null
          comentario?: string | null
          estado?: string
          fecha_fin: string
          fecha_inicio: string
          id?: string
          pedida_at?: string
          persona_id: string
          respuesta?: string | null
          resuelta_at?: string | null
          resuelta_por?: string | null
        }
        Update: {
          ausencia_id?: string | null
          comentario?: string | null
          estado?: string
          fecha_fin?: string
          fecha_inicio?: string
          id?: string
          pedida_at?: string
          persona_id?: string
          respuesta?: string | null
          resuelta_at?: string | null
          resuelta_por?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "solicitudes_vacaciones_ausencia_id_fkey"
            columns: ["ausencia_id"]
            isOneToOne: false
            referencedRelation: "ausencias"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "solicitudes_vacaciones_ausencia_id_fkey"
            columns: ["ausencia_id"]
            isOneToOne: false
            referencedRelation: "justificaciones_asistencia"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "solicitudes_vacaciones_ausencia_id_fkey"
            columns: ["ausencia_id"]
            isOneToOne: false
            referencedRelation: "vacaciones"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "solicitudes_vacaciones_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "solicitudes_vacaciones_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "solicitudes_vacaciones_resuelta_por_fkey"
            columns: ["resuelta_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "solicitudes_vacaciones_resuelta_por_fkey"
            columns: ["resuelta_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      tardanzas_justificadas: {
        Row: {
          creado_at: string
          creado_por: string
          fecha: string
          id: string
          motivo: string
          observacion: string | null
          persona_id: string
        }
        Insert: {
          creado_at?: string
          creado_por: string
          fecha: string
          id?: string
          motivo: string
          observacion?: string | null
          persona_id: string
        }
        Update: {
          creado_at?: string
          creado_por?: string
          fecha?: string
          id?: string
          motivo?: string
          observacion?: string | null
          persona_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "tardanzas_justificadas_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tardanzas_justificadas_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tardanzas_justificadas_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tardanzas_justificadas_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      tarifas_hora: {
        Row: {
          creado_por: string | null
          created_at: string
          id: string
          nota: string | null
          persona_id: string
          tarifa_hora_soles: number
          vigente_desde: string
          vigente_hasta: string | null
        }
        Insert: {
          creado_por?: string | null
          created_at?: string
          id?: string
          nota?: string | null
          persona_id: string
          tarifa_hora_soles: number
          vigente_desde: string
          vigente_hasta?: string | null
        }
        Update: {
          creado_por?: string | null
          created_at?: string
          id?: string
          nota?: string | null
          persona_id?: string
          tarifa_hora_soles?: number
          vigente_desde?: string
          vigente_hasta?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tarifas_hora_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tarifas_hora_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tarifas_hora_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tarifas_hora_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      tasas_pension: {
        Row: {
          aporte: number
          comision: number
          created_at: string
          grava_subsidio: boolean
          id: string
          nombre: string
          nota: string | null
          prima: number
          regimen: string
          vigente_desde: string
          vigente_hasta: string | null
        }
        Insert: {
          aporte: number
          comision?: number
          created_at?: string
          grava_subsidio?: boolean
          id?: string
          nombre: string
          nota?: string | null
          prima?: number
          regimen: string
          vigente_desde: string
          vigente_hasta?: string | null
        }
        Update: {
          aporte?: number
          comision?: number
          created_at?: string
          grava_subsidio?: boolean
          id?: string
          nombre?: string
          nota?: string | null
          prima?: number
          regimen?: string
          vigente_desde?: string
          vigente_hasta?: string | null
        }
        Relationships: []
      }
      terminales: {
        Row: {
          activo: boolean
          auth_user_id: string | null
          id: string
          nombre_dispositivo: string
          requiere_pin: boolean
          sede_id: string
          ultimo_visto_at: string | null
        }
        Insert: {
          activo?: boolean
          auth_user_id?: string | null
          id?: string
          nombre_dispositivo: string
          requiere_pin?: boolean
          sede_id: string
          ultimo_visto_at?: string | null
        }
        Update: {
          activo?: boolean
          auth_user_id?: string | null
          id?: string
          nombre_dispositivo?: string
          requiere_pin?: boolean
          sede_id?: string
          ultimo_visto_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "terminales_sede_id_fkey"
            columns: ["sede_id"]
            isOneToOne: false
            referencedRelation: "sedes"
            referencedColumns: ["id"]
          },
        ]
      }
      tipos_ausencia: {
        Row: {
          activo: boolean
          alerta_desde: number | null
          codigo: string
          descuenta_vacaciones: boolean
          nombre: string
          orden: number
          paga: boolean
          requiere_aprobacion: boolean
          requiere_documento: boolean
          ventana_alerta_dias: number | null
        }
        Insert: {
          activo?: boolean
          alerta_desde?: number | null
          codigo: string
          descuenta_vacaciones?: boolean
          nombre: string
          orden?: number
          paga?: boolean
          requiere_aprobacion?: boolean
          requiere_documento?: boolean
          ventana_alerta_dias?: number | null
        }
        Update: {
          activo?: boolean
          alerta_desde?: number | null
          codigo?: string
          descuenta_vacaciones?: boolean
          nombre?: string
          orden?: number
          paga?: boolean
          requiere_aprobacion?: boolean
          requiere_documento?: boolean
          ventana_alerta_dias?: number | null
        }
        Relationships: []
      }
      topes_educacion_rango: {
        Row: {
          actualizado_at: string
          rango: string
          tope_mensual: number
        }
        Insert: {
          actualizado_at?: string
          rango: string
          tope_mensual: number
        }
        Update: {
          actualizado_at?: string
          rango?: string
          tope_mensual?: number
        }
        Relationships: []
      }
      turnos: {
        Row: {
          creado_por: string | null
          created_at: string | null
          es_descanso: boolean
          fecha: string
          hora_entrada: string | null
          hora_salida: string | null
          id: string
          origen: string
          persona_id: string
        }
        Insert: {
          creado_por?: string | null
          created_at?: string | null
          es_descanso?: boolean
          fecha: string
          hora_entrada?: string | null
          hora_salida?: string | null
          id?: string
          origen?: string
          persona_id: string
        }
        Update: {
          creado_por?: string | null
          created_at?: string | null
          es_descanso?: boolean
          fecha?: string
          hora_entrada?: string | null
          hora_salida?: string | null
          id?: string
          origen?: string
          persona_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "turnos_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "turnos_creado_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "turnos_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "turnos_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      justificaciones_asistencia: {
        Row: {
          creado_at: string | null
          creado_por: string | null
          fecha: string | null
          id: string | null
          motivo: string | null
          observacion: string | null
          persona_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ausencias_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ausencias_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ausencias_registrada_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ausencias_registrada_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ausencias_tipo_fkey"
            columns: ["motivo"]
            isOneToOne: false
            referencedRelation: "tipos_ausencia"
            referencedColumns: ["codigo"]
          },
        ]
      }
      terminal_roster: {
        Row: {
          apellidos: string | null
          foto_url: string | null
          id: string | null
          nombres: string | null
          sede_codigo: string | null
          sede_nombre: string | null
        }
        Relationships: []
      }
      v_planilla_pagada: {
        Row: {
          aporte_essalud: number | null
          area_codigo: string | null
          asignacion_familiar: number | null
          bonos: number | null
          congelada_at: string | null
          congelada_por: string | null
          costo_total: number | null
          descuento_pension: number | null
          descuentos: number | null
          dias_trabajados: number | null
          fila: Json | null
          grupo: string | null
          horas_mes: number | null
          monto_descanso_semanal: number | null
          monto_educacion: number | null
          monto_feriados: number | null
          monto_movilidad: number | null
          monto_plus: number | null
          monto_sobretiempo: number | null
          nombre: string | null
          origen: string | null
          pago_base: number | null
          periodo_id: string | null
          persona_id: string | null
          provision_bonif_extraordinaria: number | null
          provision_cts: number | null
          provision_gratificacion: number | null
          provision_total: number | null
          provision_vacaciones: number | null
          rango: string | null
          retencion_4ta: number | null
          salario_ref: number | null
          sede_codigo: string | null
          total: number | null
          version: number | null
        }
        Insert: {
          aporte_essalud?: number | null
          area_codigo?: string | null
          asignacion_familiar?: number | null
          bonos?: number | null
          congelada_at?: string | null
          congelada_por?: string | null
          costo_total?: number | null
          descuento_pension?: number | null
          descuentos?: number | null
          dias_trabajados?: number | null
          fila?: Json | null
          grupo?: string | null
          horas_mes?: number | null
          monto_descanso_semanal?: number | null
          monto_educacion?: number | null
          monto_feriados?: number | null
          monto_movilidad?: number | null
          monto_plus?: number | null
          monto_sobretiempo?: number | null
          nombre?: string | null
          origen?: string | null
          pago_base?: number | null
          periodo_id?: string | null
          persona_id?: string | null
          provision_bonif_extraordinaria?: number | null
          provision_cts?: number | null
          provision_gratificacion?: number | null
          provision_total?: number | null
          provision_vacaciones?: number | null
          rango?: string | null
          retencion_4ta?: number | null
          salario_ref?: number | null
          sede_codigo?: string | null
          total?: number | null
          version?: number | null
        }
        Update: {
          aporte_essalud?: number | null
          area_codigo?: string | null
          asignacion_familiar?: number | null
          bonos?: number | null
          congelada_at?: string | null
          congelada_por?: string | null
          costo_total?: number | null
          descuento_pension?: number | null
          descuentos?: number | null
          dias_trabajados?: number | null
          fila?: Json | null
          grupo?: string | null
          horas_mes?: number | null
          monto_descanso_semanal?: number | null
          monto_educacion?: number | null
          monto_feriados?: number | null
          monto_movilidad?: number | null
          monto_plus?: number | null
          monto_sobretiempo?: number | null
          nombre?: string | null
          origen?: string | null
          pago_base?: number | null
          periodo_id?: string | null
          persona_id?: string | null
          provision_bonif_extraordinaria?: number | null
          provision_cts?: number | null
          provision_gratificacion?: number | null
          provision_total?: number | null
          provision_vacaciones?: number | null
          rango?: string | null
          retencion_4ta?: number | null
          salario_ref?: number | null
          sede_codigo?: string | null
          total?: number | null
          version?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "planilla_pagada_detalle_congelada_por_fkey"
            columns: ["congelada_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "planilla_pagada_detalle_congelada_por_fkey"
            columns: ["congelada_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "planilla_pagada_detalle_periodo_id_fkey"
            columns: ["periodo_id"]
            isOneToOne: false
            referencedRelation: "periodos_planilla"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "planilla_pagada_detalle_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "planilla_pagada_detalle_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
      vacaciones: {
        Row: {
          creado_at: string | null
          creado_por: string | null
          fecha_fin: string | null
          fecha_inicio: string | null
          id: string | null
          observacion: string | null
          persona_id: string | null
        }
        Insert: {
          creado_at?: string | null
          creado_por?: string | null
          fecha_fin?: string | null
          fecha_inicio?: string | null
          id?: string | null
          observacion?: string | null
          persona_id?: string | null
        }
        Update: {
          creado_at?: string | null
          creado_por?: string | null
          fecha_fin?: string | null
          fecha_inicio?: string | null
          id?: string | null
          observacion?: string | null
          persona_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ausencias_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ausencias_persona_id_fkey"
            columns: ["persona_id"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ausencias_registrada_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "personas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ausencias_registrada_por_fkey"
            columns: ["creado_por"]
            isOneToOne: false
            referencedRelation: "terminal_roster"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      fn_aceptar_incidencia: {
        Args: {
          p_fecha: string | null
          p_nota?: string | null
          p_persona_id: string | null
          p_tipo: string | null
          p_valor?: number | null
        }
        Returns: undefined
      }
      fn_acta_descanso: { Args: { p_referencia: string | null }; Returns: string }
      fn_acta_descanso_ubicacion: {
        Args: { p_referencia: string | null }
        Returns: {
          dataurl: string
          storage_path: string
        }[]
      }
      fn_actas_descanso: {
        Args: never
        Returns: {
          actualizado: string
          archivo_nombre: string
          peso_kb: number
          referencia: string
          registros: number
          tiene_archivo: boolean
        }[]
      }
      fn_actualizar_foto_perfil: {
        Args: { p_foto_url: string | null; p_persona_id: string | null }
        Returns: undefined
      }
      fn_acusar_documento: {
        Args: { p_documento_id: string | null; p_nombre_declarado: string | null }
        Returns: undefined
      }
      fn_acusar_politica_salarial: { Args: { p_nombre: string | null }; Returns: Json }
      fn_acuses_documento: {
        Args: { p_documento_id: string | null }
        Returns: {
          acusado_at: string
          nombre: string
          persona_id: string
          sede: string
          tiene_cuenta: boolean
          via: string
        }[]
      }
      fn_acuses_politica_salarial: {
        Args: { p_version?: number | null }
        Returns: Json
      }
      fn_agregar_marcaje: {
        Args: {
          p_motivo: string | null
          p_motivo_otro?: string | null
          p_persona_id: string | null
          p_tipo: Database["public"]["Enums"]["tipo_marca"] | null
          p_ts: string | null
        }
        Returns: {
          anulada_at: string | null
          anulada_motivo: string | null
          anulada_por: string | null
          client_uuid: string
          confirmo_sin_refrigerio: boolean | null
          estado_revision: Database["public"]["Enums"]["estado_revision"]
          fecha_jornada: string | null
          id: string
          motivo_otro: string | null
          origen: Database["public"]["Enums"]["origen_marca"]
          persona_id: string
          sede_id: string
          server_received_at: string
          terminal_id: string | null
          timestamp_marca: string
          tipo: Database["public"]["Enums"]["tipo_marca"]
        }
        SetofOptions: {
          from: "*"
          to: "marcajes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      fn_agregar_movimiento: {
        Args: {
          p_categoria?: string | null
          p_concepto: string | null
          p_monto: number | null
          p_periodo_id: string | null
          p_periodo_origen_id?: string | null
          p_persona_id: string | null
          p_tipo: string | null
        }
        Returns: undefined
      }
      fn_ahora_servidor: { Args: never; Returns: string }
      fn_alerta_despachable: {
        Args: {
          p_created_at: string | null
          p_estado: string | null
          p_intentos: number | null
          p_procesando_desde: string | null
        }
        Returns: boolean
      }
      fn_alertas_despacho_resumen: { Args: never; Returns: Json }
      fn_alertas_email_pendientes: {
        Args: never
        Returns: {
          alerta_id: string
          destinatarios: string[]
          destinatarios_nombres: string[]
          estado_previo: string
          intentos: number
          payload: Json
          persona_nombre: string
          sede_codigo: string
          tipo: string
        }[]
      }
      fn_alertas_reservar: { Args: { p_id: string | null }; Returns: boolean }
      fn_anular_anuncio: { Args: { p_id: string | null }; Returns: undefined }
      fn_anular_ausencia: {
        Args: { p_id: string | null; p_motivo: string | null }
        Returns: undefined
      }
      fn_anular_marcaje: {
        Args: { p_marcaje_id: string | null; p_motivo: string | null }
        Returns: {
          anulada_at: string | null
          anulada_motivo: string | null
          anulada_por: string | null
          client_uuid: string
          confirmo_sin_refrigerio: boolean | null
          estado_revision: Database["public"]["Enums"]["estado_revision"]
          fecha_jornada: string | null
          id: string
          motivo_otro: string | null
          origen: Database["public"]["Enums"]["origen_marca"]
          persona_id: string
          sede_id: string
          server_received_at: string
          terminal_id: string | null
          timestamp_marca: string
          tipo: Database["public"]["Enums"]["tipo_marca"]
        }
        SetofOptions: {
          from: "*"
          to: "marcajes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      fn_anuncios_vigentes: {
        Args: { p_incluir_anulados?: boolean | null }
        Returns: {
          anulado_at: string
          cuerpo: string
          id: string
          mi_leido_at: string
          publicado_at: string
          publicado_por_nombre: string
          sede_codigo: string
          sede_id: string
          titulo: string
          total_lectores: number
        }[]
      }
      fn_aplicar_cambio_perfil: {
        Args: { p_solicitud_id: string | null }
        Returns: undefined
      }
      fn_aprobar_ausencia: { Args: { p_id: string | null }; Returns: undefined }
      fn_archivo_empresa: {
        Args: never
        Returns: {
          bytes: number
          entidad: string
          estado: string
          fecha_documento: string
          id: string
          mime: string
          nombre_archivo: string
          nota: string | null
          numero: string | null
          reemplaza_a: string | null
          reemplazada_por: string | null
          retirado_at: string | null
          retirado_motivo: string | null
          retirado_por_nombre: string | null
          sede_id: string | null
          sede_nombre: string | null
          storage_path: string
          subido_at: string
          subido_por_nombre: string | null
          titulo: string
          vence_el: string | null
        }[]
      }
      fn_archivo_libre: { Args: { p_path: string | null }; Returns: boolean }
      fn_archivo_retirar: {
        Args: { p_id: string | null; p_motivo: string | null }
        Returns: undefined
      }
      fn_archivo_subir: {
        Args: {
          p_entidad: string | null
          p_fecha_documento: string | null
          p_nombre_archivo: string | null
          p_nota: string | null
          p_numero: string | null
          p_reemplaza_a?: string | null
          p_sede_id: string | null
          p_storage_path: string | null
          p_titulo: string | null
          p_vence_el: string | null
        }
        Returns: string
      }
      fn_area_activa: {
        Args: { p_activa: boolean | null; p_codigo: string | null }
        Returns: undefined
      }
      fn_areas: { Args: never; Returns: Json }
      fn_atender_revision: {
        Args: { p_id: string | null; p_respuesta: string | null }
        Returns: undefined
      }
      fn_atender_revision_contrato: {
        Args: { p_id: string | null; p_respuesta: string | null }
        Returns: undefined
      }
      fn_atender_revision_movilidad: {
        Args: { p_id: string | null; p_respuesta: string | null }
        Returns: undefined
      }
      fn_ausencia_adjuntar_certificado: {
        Args: { p_ausencia_id: string | null; p_storage_path: string | null }
        Returns: undefined
      }
      fn_ausencia_dias_con_jornada: {
        Args: {
          p_fecha_fin: string | null
          p_fecha_inicio: string | null
          p_persona_id: string | null
        }
        Returns: {
          fecha: string
          horas_trabajadas: number
        }[]
      }
      fn_ausencias: {
        Args: { p_desde: string | null; p_hasta: string | null; p_persona_id?: string | null }
        Returns: {
          anulada: boolean
          anulada_motivo: string
          aprobada: boolean
          dias: number
          doc_colegiatura: string
          doc_fecha: string
          doc_profesional: string
          fecha_fin: string
          fecha_inicio: string
          id: string
          motivo: string
          nombre: string
          paga: boolean
          persona_id: string
          registrada_at: string
          registrada_por_nombre: string
          registrada_tarde: boolean
          requiere_aprobacion: boolean
          sede: string
          tipo: string
          tipo_nombre: string
        }[]
      }
      fn_ausencias_alerta: {
        Args: { p_persona_id?: string | null }
        Returns: {
          nombre: string
          persona_id: string
          tipo: string
          tipo_nombre: string
          umbral: number
          veces: number
          ventana_dias: number
        }[]
      }
      fn_ausencias_resumen: {
        Args: { p_desde: string | null; p_hasta: string | null }
        Returns: {
          dias_no_pagados: number
          dias_pagados: number
          dias_total: number
          persona_id: string
          por_tipo: Json
          registros: number
        }[]
      }
      fn_ausencias_subsidio: {
        Args: { p_anio?: number | null }
        Returns: {
          avisar_desde: number
          con_certificado: number
          dias_calendario: number
          dias_para_el_umbral: number
          hay_que_avisar: boolean
          nombre: string
          persona_id: string
          sin_certificado: number
          umbral: number
        }[]
      }
      fn_auto_cierre: { Args: never; Returns: number }
      fn_avisos_vinculo: {
        Args: never
        Returns: {
          aviso: string
          cumple_el_mes: string
          dias: number
          fecha_ingreso: string
          persona: string
          persona_id: string
          sede: string
          tipo_vinculo: string
          ya_devenga: boolean
        }[]
      }
      fn_bandeja_marcar_visto: {
        Args: { p_item_id: string | null; p_tipo_item: string | null }
        Returns: undefined
      }
      fn_beneficio_ya_depositado: {
        Args: { p_anio: number | null; p_persona_id: string | null; p_ventana: string | null }
        Returns: number
      }
      fn_boleta_anular: {
        Args: { p_boleta_id: string | null; p_motivo: string | null }
        Returns: undefined
      }
      fn_boleta_archivo_libre: { Args: { p_path: string | null }; Returns: boolean }
      fn_boleta_confirmar_recibo: {
        Args: { p_version_id: string | null }
        Returns: undefined
      }
      fn_boleta_guardar_version: {
        Args: {
          p_avisar?: boolean | null
          p_nota?: string | null
          p_partes: Json | null
          p_periodo_id: string | null
          p_persona_id: string | null
          p_tipo: string | null
        }
        Returns: string
      }
      fn_boleta_marcar_papel: {
        Args: { p_periodo_id: string | null; p_persona_id: string | null }
        Returns: string
      }
      fn_boleta_partes: {
        Args: { p_version_id: string | null }
        Returns: {
          bytes: number
          mime: string
          orden: number
          storage_path: string
        }[]
      }
      fn_boleta_puede_ver: { Args: { p_path: string | null }; Returns: boolean }
      fn_boleta_versiones: {
        Args: { p_boleta_id: string | null }
        Returns: {
          avisar: boolean
          bytes: number
          creada_at: string
          creada_por: string
          n: number
          n_partes: number
          nota: string | null
          recibida_at: string | null
          tipo: string
          version_id: string
          vigente: boolean
          vista_at: string | null
        }[]
      }
      fn_boletas_publicar: {
        Args: { p_periodo_id: string | null; p_personas?: string[] | null }
        Returns: number
      }
      fn_boletas_tablero: {
        Args: { p_periodo_id: string | null }
        Returns: {
          actualizada: boolean
          boleta_id: string | null
          bytes: number
          cargo: string | null
          estado: string
          grupo_pagado: boolean
          n_partes: number
          nombre: string
          persona_id: string
          publicada_at: string | null
          recibida_at: string | null
          sede_codigo: string
          tiene_cuenta: boolean
          tipo: string | null
          tipo_vinculo: string
          version_id: string | null
          version_n: number | null
          vista_at: string | null
        }[]
      }
      fn_bono_monto_vigente: { Args: never; Returns: number }
      fn_bonos_por_transferir: {
        Args: never
        Returns: {
          anio: number
          documento_id: string
          monto: number
          pedido_at: string
          pedido_el: string
          persona: string
          persona_id: string
          sede: string
        }[]
      }
      fn_borrar_dni_de: {
        Args: { p_motivo: string | null; p_persona_id: string | null }
        Returns: {
          ruta: string
        }[]
      }
      fn_calcular_metricas_jornada: {
        Args: {
          p_entrada_ts: string | null
          p_fecha: string | null
          p_hora_entrada_prog: string | null
          p_hora_salida_prog: string | null
          p_horas_trabajadas: number | null
          p_refri_prog: number | null
          p_salida_final_origen: Database["public"]["Enums"]["origen_marca"] | null
          p_salida_final_revision: Database["public"]["Enums"]["estado_revision"] | null
          p_salida_final_ts: string | null
          p_sujeta_a_horario: boolean | null
        }
        Returns: {
          horas_extra_detectadas: number
          minutos_salida_temprana: number
          minutos_tarde: number
        }[]
      }
      fn_cambiar_regimen_pension: {
        Args: {
          p_desde: string | null
          p_nota?: string | null
          p_persona_id: string | null
          p_regimen: string | null
        }
        Returns: Json
      }
      fn_cancelar_solicitud_vacaciones: {
        Args: { p_id: string | null }
        Returns: undefined
      }
      fn_cargo_de_rol: {
        Args: { p_rol: Database["public"]["Enums"]["rol_usuario"] | null }
        Returns: string
      }
      fn_casos_resumen: {
        Args: { p_desde?: string | null }
        Returns: {
          estado: string
          mes: string
          sede_codigo: string
          sede_id: string
          tipo: string
          vencido: boolean
          via: string
        }[]
      }
      fn_cerrar_derechohabiente: {
        Args: { p_hasta?: string | null; p_id: string | null }
        Returns: undefined
      }
      fn_cesar_persona: {
        Args: {
          p_fecha_cese: string | null
          p_motivo: string | null
          p_persona_id: string | null
          p_tipo_vinculo?: string | null
        }
        Returns: undefined
      }
      fn_cierre_lima: { Args: { p_fecha: string | null }; Returns: string }
      fn_conducta_antecedentes: {
        Args: {
          p_fecha_hecho?: string | null
          p_literal: string | null
          p_numeral: string | null
          p_persona_id: string | null
        }
        Returns: Json
      }
      fn_confirmar_auto_cierre: {
        Args: { p_marcaje_id: string | null; p_motivo?: string | null }
        Returns: {
          anulada_at: string | null
          anulada_motivo: string | null
          anulada_por: string | null
          client_uuid: string
          confirmo_sin_refrigerio: boolean | null
          estado_revision: Database["public"]["Enums"]["estado_revision"]
          fecha_jornada: string | null
          id: string
          motivo_otro: string | null
          origen: Database["public"]["Enums"]["origen_marca"]
          persona_id: string
          sede_id: string
          server_received_at: string
          terminal_id: string | null
          timestamp_marca: string
          tipo: Database["public"]["Enums"]["tipo_marca"]
        }
        SetofOptions: {
          from: "*"
          to: "marcajes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      fn_confirmar_entrega_bono: {
        Args: { p_documento_id: string | null; p_fecha: string | null }
        Returns: string
      }
      fn_confirmar_mi_bono_cumpleanos: { Args: never; Returns: string }
      fn_confirmar_mi_declaracion_ruta: {
        Args: {
          p_costo_pasaje?: number | null
          p_costo_taxi?: number | null
          p_distrito: string | null
          p_frecuencia_taxi?: number | null
          p_medios_ida: number | null
          p_medios_vuelta: number | null
          p_provincia: string | null
        }
        Returns: string
      }
      fn_confirmar_mi_firma_contrato: {
        Args: { p_contrato_id: string | null }
        Returns: undefined
      }
      fn_contrato_anular: {
        Args: { p_id: string | null; p_motivo: string | null }
        Returns: undefined
      }
      fn_contrato_editar: {
        Args: {
          p_cargo?: string | null
          p_datos_formulario?: Json | null
          p_documento_html?: string | null
          p_fecha_fin?: string | null
          p_fecha_inicio?: string | null
          p_id?: string | null
          p_remuneracion_mensual?: number | null
          p_tipo?: string | null
        }
        Returns: string
      }
      fn_contrato_firmado_vigente_de: {
        Args: { p_persona_id: string | null }
        Returns: {
          anulado_at: string | null
          anulado_motivo: string | null
          anulado_por: string | null
          cargo: string
          comunicado_mtpe_at: string | null
          copia_entregada_at: string | null
          datos_formulario: Json | null
          documento_html: string
          editado_at: string | null
          editado_por: string | null
          fecha_fin: string | null
          fecha_firma: string | null
          fecha_inicio: string
          firma_persona: string | null
          firma_persona_confirmada_at: string | null
          generado_at: string
          generado_por: string
          horas_semanales: number | null
          id: string
          persona_id: string
          registrado_por: string | null
          remuneracion_mensual: number
          sede_id: string
          storage_path: string | null
          tipo: string
        }
        SetofOptions: {
          from: "*"
          to: "contratos_generados"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      fn_contrato_marcar_tramite: {
        Args: { p_fecha?: string | null; p_id: string | null; p_tramite: string | null }
        Returns: undefined
      }
      fn_contrato_puede_ver: { Args: { p_path: string | null }; Returns: boolean }
      fn_contrato_refrescar_vencimiento: {
        Args: {
          p_motivo: string | null
          p_persona_id: string | null
          p_puede_borrar?: boolean | null
        }
        Returns: string
      }
      fn_contrato_registrar: {
        Args: {
          p_cargo?: string | null
          p_datos_formulario?: Json | null
          p_documento_html?: string | null
          p_fecha_fin?: string | null
          p_fecha_firma?: string | null
          p_fecha_inicio?: string | null
          p_horas_semanales?: number | null
          p_id?: string | null
          p_persona_id?: string | null
          p_remuneracion_mensual?: number | null
          p_sede_id?: string | null
          p_storage_path?: string | null
          p_tipo?: string | null
        }
        Returns: string
      }
      fn_contrato_revisiones_pedidas: {
        Args: { p_solo_pendientes?: boolean | null }
        Returns: Json
      }
      fn_contratos_desnaturalizados: {
        Args: never
        Returns: {
          dias_marcados_despues: number
          fecha_fin_contrato: string
          nombre: string
          persona_id: string
          primer_dia_despues: string
          sede: string
          ultimo_dia_marcado: string
        }[]
      }
      fn_contratos_listar: {
        Args: { p_persona_id?: string | null }
        Returns: {
          anulado_at: string
          anulado_motivo: string
          cargo: string
          comunicado_mtpe_at: string
          copia_entregada_at: string
          editado_at: string
          editado_por: string
          fecha_fin: string
          fecha_firma: string
          fecha_inicio: string
          firma_persona_confirmada_at: string
          generado_at: string
          generado_por: string
          horas_semanales: number
          id: string
          persona: string
          persona_id: string
          remuneracion_mensual: number
          sede: string
          storage_path: string
          tipo: string
          vigente: boolean
        }[]
      }
      fn_contratos_por_vencer: {
        Args: { p_dias?: number | null }
        Returns: {
          dias_restantes: number
          fecha_fin_contrato: string
          nombre: string
          persona_id: string
          sede: string
          ya_vencio: boolean
        }[]
      }
      fn_contratos_tablero: {
        Args: never
        Returns: {
          comunicado_mtpe_at: string
          contrato_id: string
          copia_entregada_at: string
          copia_vence: string
          dias_marcados_despues: number
          dias_restantes: number
          estado: string
          fecha_fin_contrato: string
          fecha_firma: string
          mtpe_vence: string
          persona: string
          persona_id: string
          sede: string
          tipo: string
        }[]
      }
      fn_copiar_semana_anterior: {
        Args: { p_lunes_destino: string | null; p_sede_id: string | null }
        Returns: {
          fecha: string
          persona_id: string
          resultado: string
        }[]
      }
      fn_corregir_horario_retroactivo: {
        Args: {
          p_horario: Json | null
          p_motivo: string | null
          p_persona_id: string | null
          p_vigente_desde: string | null
        }
        Returns: undefined
      }
      fn_corregir_marca: {
        Args: {
          p_marcaje_id: string | null
          p_motivo?: string | null
          p_nuevo_tipo?: Database["public"]["Enums"]["tipo_marca"] | null
          p_nuevo_ts?: string | null
        }
        Returns: {
          anulada_at: string | null
          anulada_motivo: string | null
          anulada_por: string | null
          client_uuid: string
          confirmo_sin_refrigerio: boolean | null
          estado_revision: Database["public"]["Enums"]["estado_revision"]
          fecha_jornada: string | null
          id: string
          motivo_otro: string | null
          origen: Database["public"]["Enums"]["origen_marca"]
          persona_id: string
          sede_id: string
          server_received_at: string
          terminal_id: string | null
          timestamp_marca: string
          tipo: Database["public"]["Enums"]["tipo_marca"]
        }
        SetofOptions: {
          from: "*"
          to: "marcajes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      fn_corregir_marcaje: {
        Args: { p_marcaje_id: string | null; p_motivo: string | null; p_nuevo_ts: string | null }
        Returns: {
          anulada_at: string | null
          anulada_motivo: string | null
          anulada_por: string | null
          client_uuid: string
          confirmo_sin_refrigerio: boolean | null
          estado_revision: Database["public"]["Enums"]["estado_revision"]
          fecha_jornada: string | null
          id: string
          motivo_otro: string | null
          origen: Database["public"]["Enums"]["origen_marca"]
          persona_id: string
          sede_id: string
          server_received_at: string
          terminal_id: string | null
          timestamp_marca: string
          tipo: Database["public"]["Enums"]["tipo_marca"]
        }
        SetofOptions: {
          from: "*"
          to: "marcajes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      fn_costos_planilla: {
        Args: { p_desde: string | null; p_hasta: string | null }
        Returns: Json
      }
      fn_crear_periodo: {
        Args: { p_fecha_fin: string | null; p_fecha_ini?: string | null }
        Returns: Json
      }
      fn_crear_persona: {
        Args: {
          p_apellidos: string | null
          p_confirmo_distinta?: boolean | null
          p_documento?: string | null
          p_email: string | null
          p_es_estacion?: boolean | null
          p_funcion: string | null
          p_nombres: string | null
          p_pin_hash: string | null
          p_rol: string | null
          p_sede_base_id: string | null
          p_tipo_documento?: string | null
        }
        Returns: Json
      }
      fn_crear_solicitud_perfil: {
        Args: {
          p_campo: string | null
          p_rutas_adjuntas?: string[] | null
          p_valor_propuesto: Json | null
        }
        Returns: string
      }
      fn_cts_trunca: {
        Args: { p_fecha_cese: string | null; p_persona_id: string | null }
        Returns: Json
      }
      fn_cuadro_categorias: { Args: never; Returns: Json }
      fn_dcs_por_que_no_compensa: {
        Args: {
          p_fecha_descanso: string | null
          p_fecha_feriado: string | null
          p_persona_id: string | null
        }
        Returns: string
      }
      fn_devenga: {
        Args: { p_beneficio: string | null; p_persona_id: string | null }
        Returns: boolean
      }
      fn_devenga_algo: { Args: { p_persona_id: string | null }; Returns: boolean }
      fn_devenga_beneficios: { Args: { p_tipo: string | null }; Returns: boolean }
      fn_dia_incoherente: {
        Args: { p_fecha: string | null; p_persona_id: string | null }
        Returns: boolean
      }
      fn_dia_suspendido: {
        Args: { p_fecha: string | null; p_persona_id: string | null }
        Returns: boolean
      }
      fn_dias_por_revisar: {
        Args: { p_limite?: number | null }
        Returns: {
          fecha: string
          marcas: number
          motivo: string
          nombre: string
          periodo_pagado: boolean
          persona_id: string
          sede: string
        }[]
      }
      fn_dias_suspension: {
        Args: { p_desde: string | null; p_dias: number | null; p_persona_id: string | null }
        Returns: {
          fecha: string
        }[]
      }
      fn_documento_anular: {
        Args: { p_id: string | null; p_motivo: string | null }
        Returns: undefined
      }
      fn_documento_error: {
        Args: { p_numero: string | null; p_tipo: string | null }
        Returns: string
      }
      fn_documento_forma_valida: {
        Args: { p_numero: string | null; p_tipo: string | null }
        Returns: boolean
      }
      fn_documento_puede_ver: { Args: { p_path: string | null }; Returns: boolean }
      fn_documento_registrar: {
        Args: {
          p_anio?: number | null
          p_es_negativa?: boolean | null
          p_fecha_firma: string | null
          p_id?: string | null
          p_monto_declarado?: number | null
          p_nota?: string | null
          p_persona_id?: string | null
          p_ruta_declarada?: string | null
          p_storage_path?: string | null
          p_tipo: string | null
        }
        Returns: string
      }
      fn_documentos_estado_politica: {
        Args: never
        Returns: {
          cargada: boolean
          fecha_firma: string
          id: string
          llego_tarde: boolean
          primer_pago: string
          storage_path: string
        }[]
      }
      fn_documentos_listar: {
        Args: { p_persona_id?: string | null }
        Returns: {
          alcance: string
          anio: number
          anulado_at: string
          anulado_motivo: string
          es_negativa: boolean
          fecha_firma: string
          firma_persona: string
          id: string
          monto_declarado: number
          nota: string
          persona: string
          persona_id: string
          registrado_por: string
          ruta_costo_pasaje: number
          ruta_costo_taxi: number
          ruta_declarada: string
          ruta_distrito: string
          ruta_frecuencia_taxi: number
          ruta_gasto_diario: number
          ruta_medios_ida: number
          ruta_medios_vuelta: number
          ruta_provincia: string
          storage_path: string
          tipo: string
          vigente: boolean
        }[]
      }
      fn_documentos_tablero: {
        Args: { p_solo_mi_fila?: boolean | null }
        Returns: {
          bono_anio: number
          bono_estado: string
          bono_firmada_el: string
          bono_id: string
          bono_mes: number
          estado: string
          fecha_ingreso: string
          persona: string
          persona_id: string
          ruta_desfasada: boolean
          ruta_firma_persona_confirmada_at: string
          ruta_firmada_el: string
          ruta_id: string
          ruta_monto: number
          ruta_negativa: boolean
          ruta_por_renovar: string
          ruta_tarifa_vigente: number
          sede: string
        }[]
      }
      fn_documentos_vigentes: {
        Args: never
        Returns: {
          documento: string
          documento_id: string
          etiqueta_version: string
          mi_acuse_at: string
          poblacion: number
          publicado_at: string
          requiere_acuse: boolean
          tipo: string
          tipo_nombre: string
          titulo: string
          total_acuses: number
          version: number
          vigente_desde: string
        }[]
      }
      fn_educacion_adjuntar_comprobante: {
        Args: {
          p_asignacion_id: string | null
          p_mes_cubierto: string | null
          p_nota?: string | null
          p_storage_path: string | null
        }
        Returns: string
      }
      fn_educacion_atender_aviso_fin: {
        Args: { p_id: string | null; p_respuesta?: string | null }
        Returns: undefined
      }
      fn_educacion_avanzar_calendario: {
        Args: { p_entrega_id: string | null }
        Returns: undefined
      }
      fn_educacion_avisar_fin: {
        Args: {
          p_asignacion_id: string | null
          p_motivo: string | null
          p_ultimo_pago?: string | null
        }
        Returns: string
      }
      fn_educacion_avisos_fin_pendientes: {
        Args: never
        Returns: {
          asignacion_id: string
          creado_at: string
          familia_id: string
          id: string
          institucion: string
          motivo: string
          persona: string
          persona_id: string
          sede: string
          ultimo_pago: string
        }[]
      }
      fn_educacion_candidatos: {
        Args: never
        Returns: {
          persona: string
          persona_id: string
          rango: string
          sede: string
          tope: number
        }[]
      }
      fn_educacion_cerrar: {
        Args: { p_hasta: string | null; p_id: string | null; p_motivo?: string | null }
        Returns: undefined
      }
      fn_educacion_configurar: {
        Args: {
          p_dias_aviso_colab: number | null
          p_dias_aviso_do: number | null
          p_dias_plazo: number | null
          p_texto_valido: string | null
        }
        Returns: undefined
      }
      fn_educacion_desde_cuando_puede_regir: { Args: never; Returns: string }
      fn_educacion_entregas: {
        Args: { p_familia_id: string | null }
        Returns: {
          archivos: Json
          asignacion_id: string
          enviada_at: string
          enviada_por: string
          estado: string
          fecha_pago: string
          id: string
          motivo_categoria: string
          motivo_comentario: string
          nota: string
          origen: string
          proxima_fecha_pago: string
          reemplaza_a: string
          retirada_at: string
          revisada_at: string
          revisada_por: string
          tipo: string
        }[]
      }
      fn_educacion_entregas_pendientes: {
        Args: never
        Returns: {
          archivos: number
          enviada_at: string
          es_reenvio: boolean
          familia_id: string
          fecha_pago: string
          id: string
          institucion: string
          persona: string
          persona_id: string
          sede: string
          tipo: string
        }[]
      }
      fn_educacion_enviar_entrega: {
        Args: {
          p_archivos: Json | null
          p_asignacion_id: string | null
          p_fecha_pago: string | null
          p_id: string | null
          p_nota?: string | null
          p_proxima_fecha_pago: string | null
          p_reemplaza_a?: string | null
          p_tipo: string | null
        }
        Returns: string
      }
      fn_educacion_fecha_pagada: {
        Args: { p_fecha: string | null; p_persona_id: string | null }
        Returns: boolean
      }
      fn_educacion_fijar_calendario: {
        Args: {
          p_asignacion_id: string | null
          p_frecuencia: string | null
          p_proxima: string | null
        }
        Returns: undefined
      }
      fn_educacion_limite_comprobante: {
        Args: never
        Returns: {
          limite_bytes: number
          tipos: string[]
        }[]
      }
      fn_educacion_listar: {
        Args: never
        Returns: {
          beneficiario: string
          beneficiario_nombre: string
          cobertura_pct: number
          comprobante_url: string
          costo_declarado: number
          dias_para_vencer: number
          id: string
          institucion: string
          meses_sin_papel: number
          monto: number
          nota: string
          paga: boolean
          papeles: number
          persona: string
          persona_id: string
          rango: string
          registrada_por: string
          sede: string
          semaforo: string
          vigente_desde: string
          vigente_hasta: string
        }[]
      }
      fn_educacion_mes_del_periodo: {
        Args: { p_fecha: string | null }
        Returns: string
      }
      fn_educacion_meses_del_tramo: {
        Args: { p_desde: string | null; p_hasta: string | null }
        Returns: string[]
      }
      fn_educacion_meses_sin_papel: {
        Args: { p_asignacion_id: string | null }
        Returns: string[]
      }
      fn_educacion_monto: {
        Args: {
          p_costo: number | null
          p_desde: string | null
          p_excluir?: string | null
          p_hasta: string | null
          p_persona_id: string | null
        }
        Returns: number
      }
      fn_educacion_papeles: {
        Args: { p_asignacion_id: string | null }
        Returns: {
          created_at: string
          id: string
          mes_cubierto: string
          nota: string
          storage_path: string
          subido_por: string
        }[]
      }
      fn_educacion_parametro: {
        Args: { p_clave: string | null; p_defecto: number | null }
        Returns: number
      }
      fn_educacion_plazo: { Args: { p_fecha_pago: string | null }; Returns: string }
      fn_educacion_por_atender: { Args: never; Returns: number }
      fn_educacion_puede_subir_entrega: {
        Args: { p_path: string | null }
        Returns: boolean
      }
      fn_educacion_puede_subir_solicitud: {
        Args: { p_path: string | null }
        Returns: boolean
      }
      fn_educacion_puede_ver: { Args: { p_path: string | null }; Returns: boolean }
      fn_educacion_quitar_comprobante: {
        Args: { p_id: string | null; p_motivo: string | null }
        Returns: undefined
      }
      fn_educacion_realinear: {
        Args: { p_actor?: string | null; p_desde: string | null; p_persona_id: string | null }
        Returns: number
      }
      fn_educacion_refrescar_espejo: {
        Args: { p_familia_id: string | null }
        Returns: undefined
      }
      fn_educacion_registrar: {
        Args: {
          p_beneficiario: string | null
          p_beneficiario_nombre?: string | null
          p_comprobante_url?: string | null
          p_costo_declarado: number | null
          p_id?: string | null
          p_institucion: string | null
          p_motivo?: string | null
          p_nota?: string | null
          p_persona_id: string | null
          p_vigente_desde: string | null
          p_vigente_hasta: string | null
        }
        Returns: string
      }
      fn_educacion_resolver_entrega: {
        Args: {
          p_aprobar: boolean | null
          p_categoria?: string | null
          p_comentario?: string | null
          p_id: string | null
        }
        Returns: undefined
      }
      fn_educacion_resolver_solicitud: {
        Args: { p_aprobar: boolean | null; p_id: string | null; p_motivo?: string | null }
        Returns: string
      }
      fn_educacion_retirar_entrega: {
        Args: { p_id: string | null }
        Returns: undefined
      }
      fn_educacion_retirar_solicitud: {
        Args: { p_id: string | null }
        Returns: undefined
      }
      fn_educacion_ruta_congelada: {
        Args: { p_path: string | null }
        Returns: boolean
      }
      fn_educacion_saldo: {
        Args: {
          p_desde: string | null
          p_excluir?: string | null
          p_hasta: string | null
          p_persona_id: string | null
        }
        Returns: number
      }
      fn_educacion_situacion: {
        Args: never
        Returns: {
          aprobadas: number
          asignacion_id: string
          aviso_fin_id: string
          aviso_fin_motivo: string
          beneficiario: string
          beneficiario_nombre: string
          dias_para_pago: number
          dias_para_plazo: number
          entrega_archivos: number
          entrega_enviada_at: string
          entrega_estado: string
          entrega_id: string
          estado_constancia: string
          familia_id: string
          fecha_pago_constancia: string
          frecuencia_pago: string
          institucion: string
          monto: number
          motivo_categoria: string
          motivo_comentario: string
          paga: boolean
          pago_proximo: boolean
          persona: string
          persona_id: string
          plazo: string
          proxima_fecha_pago: string
          rango: string
          sede: string
          vigencia: string
          vigente_desde: string
          vigente_hasta: string
        }[]
      }
      fn_educacion_solicitar: {
        Args: {
          p_beneficiario: string | null
          p_beneficiario_nombre?: string | null
          p_comprobante_url?: string | null
          p_costo_declarado: number | null
          p_institucion: string | null
          p_nota?: string | null
          p_vigente_desde?: string | null
          p_vigente_hasta?: string | null
        }
        Returns: string
      }
      fn_educacion_solicitudes_pendientes: {
        Args: never
        Returns: {
          comprobante_url: string | null
          costo_declarado: number
          enviada_at: string
          id: string
          institucion: string
          persona: string
          persona_id: string
          sede: string
          vigente_desde: string
          vigente_hasta: string
        }[]
      }
      fn_educacion_tope: {
        Args: { p_fecha: string | null; p_persona_id: string | null }
        Returns: number
      }
      fn_eliminar_marcaje: {
        Args: { p_marcaje_id: string | null; p_motivo: string | null }
        Returns: undefined
      }
      fn_eliminar_periodo: {
        Args: { p_periodo_id: string | null }
        Returns: undefined
      }
      fn_enviar_mensaje_encargada: {
        Args: { p_mensaje: string | null }
        Returns: string
      }
      fn_es_admin_o_lider: { Args: never; Returns: boolean }
      fn_es_dia_laborable: {
        Args: { p_fecha: string | null; p_persona_id: string | null }
        Returns: boolean
      }
      fn_exigir_admin: { Args: never; Returns: string }
      fn_expediente_adjuntar: {
        Args: {
          p_documento_id: string | null
          p_fecha_entrega?: string | null
          p_nota?: string | null
          p_path: string | null
          p_tipo?: string | null
        }
        Returns: string
      }
      fn_expediente_anular: {
        Args: { p_id: string | null; p_motivo: string | null }
        Returns: undefined
      }
      fn_expediente_cerrar_sin_entrega: {
        Args: { p_id: string | null; p_motivo?: string | null }
        Returns: undefined
      }
      fn_expediente_comunicar_cargos: {
        Args: { p_dias?: number | null; p_id: string | null; p_nota?: string | null }
        Returns: string
      }
      fn_expediente_correlativo: {
        Args: { p_prefijo: string | null }
        Returns: string
      }
      fn_expediente_crear_borrador: {
        Args: {
          p_doc_previo_id?: string | null
          p_hechos?: Json | null
          p_nivel: string | null
          p_observacion?: string | null
          p_periodo_desde?: string | null
          p_periodo_hasta?: string | null
          p_persona_id: string | null
          p_suspension_desde?: string | null
          p_suspension_dias?: number | null
          p_suspension_hasta?: string | null
          p_tipo_causal: string | null
        }
        Returns: string
      }
      fn_expediente_crear_conducta: {
        Args: {
          p_conocido_el: string | null
          p_fecha_hecho: string | null
          p_literal: string | null
          p_nivel: string | null
          p_numeral: string | null
          p_persona_id: string | null
          p_relato: string | null
        }
        Returns: string
      }
      fn_expediente_declarar_cargos_comunicados: {
        Args: {
          p_constancia: string | null
          p_dias?: number | null
          p_fecha: string | null
          p_id: string | null
        }
        Returns: string
      }
      fn_expediente_devolver_caso: {
        Args: { p_id: string | null; p_motivo: string | null }
        Returns: undefined
      }
      fn_expediente_doc_code: {
        Args: { p_nivel: string | null; p_tipo: string | null }
        Returns: string
      }
      fn_expediente_editar_borrador: {
        Args: {
          p_fecha_cese?: string | null
          p_hechos?: Json | null
          p_id: string | null
          p_observacion?: string | null
          p_suspension_desde?: string | null
          p_suspension_dias?: number | null
          p_suspension_hasta?: string | null
        }
        Returns: undefined
      }
      fn_expediente_entregar: {
        Args: {
          p_fecha?: string | null
          p_id: string | null
          p_medio: string | null
          p_testigo_id?: string | null
          p_testigo_nombre?: string | null
        }
        Returns: undefined
      }
      fn_expediente_firmante_motivo: {
        Args: { p_firmante: string | null; p_nivel: string | null; p_persona: string | null }
        Returns: string
      }
      fn_expediente_firmantes: {
        Args: { p_id: string | null }
        Returns: {
          cargo: string
          nombre: string
          persona_id: string
          tiene_firma: boolean
        }[]
      }
      fn_expediente_enviar_a_info: {
        Args: { p_id: string | null }
        Returns: undefined
      }
      fn_expediente_firmar: {
        Args: { p_firmante_id?: string | null; p_id: string | null }
        Returns: string
      }
      fn_expediente_generar_falta: {
        Args: { p_persona_id: string | null }
        Returns: string
      }
      fn_expediente_generar_tardanza: {
        Args: { p_mes?: string | null; p_persona_id: string | null }
        Returns: string
      }
      fn_expediente_puede_actuar: {
        Args: { p_nivel: string | null; p_persona_id: string | null }
        Returns: boolean
      }
      fn_expediente_puede_adjuntar: {
        Args: { p_path: string | null }
        Returns: boolean
      }
      fn_expediente_puede_recibir_descargo: {
        Args: { p_id: string | null }
        Returns: boolean
      }
      fn_expediente_puede_suscribir: {
        Args: { p_nivel: string | null; p_rol: string | null }
        Returns: boolean
      }
      fn_expediente_reabrir: { Args: { p_id: string | null }; Returns: undefined }
      fn_expediente_resolver: {
        Args: { p_id: string | null; p_motivo: string | null; p_resultado: string | null }
        Returns: undefined
      }
      fn_expediente_retirar_de_info: {
        Args: { p_id: string | null }
        Returns: undefined
      }
      fn_expediente_set_suspension: {
        Args: { p_desde: string | null; p_dias: number | null; p_id: string | null }
        Returns: {
          fecha: string
        }[]
      }
      fn_expediente_tomar_caso: {
        Args: { p_id: string | null; p_motivo: string | null }
        Returns: undefined
      }
      fn_expediente_valorar_descargo: {
        Args: { p_acogido: string | null; p_id: string | null; p_valoracion: string | null }
        Returns: undefined
      }
      fn_falta_contadores: {
        Args: { p_desde: string | null; p_persona_id: string | null }
        Returns: {
          consecutivas: number
          en_180: number
          en_30: number
          fechas: string[]
        }[]
      }
      fn_faltas: {
        Args: { p_desde: string | null; p_hasta: string | null }
        Returns: {
          fecha: string
          justificada: boolean
          motivo: string
          nombre: string
          persona_id: string
          sede: string
        }[]
      }
      fn_faltas_resumen: {
        Args: { p_as_of?: string | null }
        Returns: {
          consecutivas: number
          en_180: number
          en_30: number
          nivel: string
          nombre: string
          persona_id: string
          sede: string
        }[]
      }
      fn_familia_marca: {
        Args: { p_tipo: Database["public"]["Enums"]["tipo_marca"] | null }
        Returns: string
      }
      fn_fecha_de_jornada: {
        Args: { p_fecha_jornada: string | null; p_timestamp_marca: string | null }
        Returns: string
      }
      fn_fecha_en_periodo_pagado: {
        Args: { p_fecha: string | null; p_persona_id: string | null }
        Returns: boolean
      }
      fn_fecha_limite_asistencia: {
        Args: { p_persona_id: string | null }
        Returns: string
      }
      fn_feriado_devengado: {
        Args: {
          p_desde: string | null
          p_dias: number | null
          p_hasta: string | null
          p_persona: string | null
          p_salario_asof?: string | null
        }
        Returns: Json
      }
      fn_feriado_devengado_nucleo: {
        Args: {
          p_desde: string | null
          p_dias: number | null
          p_hasta: string | null
          p_persona: string | null
          p_salario_asof?: string | null
        }
        Returns: Json
      }
      fn_feriados: { Args: { p_anio: number | null }; Returns: Json }
      fn_feriados_cobertura: {
        Args: never
        Returns: {
          mensaje: string
          meses_restantes: number
          nivel: string
          ultimo_feriado: string
        }[]
      }
      fn_feriados_laborados: {
        Args: { p_desde: string | null; p_hasta: string | null }
        Returns: {
          acta_ref: string
          dcs_id: string
          estado: string
          fecha_descanso: string
          fecha_feriado: string
          feriado_nombre: string
          horas: number
          motivo_fuera_de_plazo: string
          no_compensa_porque: string
          nombre: string
          persona_id: string
          sede: string
          sobretasa: number
        }[]
      }
      fn_fijar_base_declarada: {
        Args: {
          p_monto: number | null
          p_omitir?: string[] | null
          p_rango: string | null
          p_vigente_desde: string | null
        }
        Returns: {
          base_anterior: number
          persona_id: string
          salario_anterior: number
        }[]
      }
      fn_firma_de_memo: { Args: { p_doc_id: string | null }; Returns: string }
      fn_firma_empresa: { Args: never; Returns: string }
      fn_firma_persona: { Args: { p_persona_id: string | null }; Returns: string }
      fn_firmantes_disponibles: {
        Args: never
        Returns: {
          id: string
          nombre: string
        }[]
      }
      fn_firmar_memo_como_sancionado: {
        Args: { p_id: string | null }
        Returns: undefined
      }
      fn_foto_perfil_puede_escribir: {
        Args: { p_path: string | null }
        Returns: boolean
      }
      fn_generar_alertas_vencimiento: { Args: never; Returns: number }
      fn_grati_cts_agregar_pendientes: {
        Args: { p_periodo_id: string | null }
        Returns: Json
      }
      fn_grati_cts_periodo: { Args: { p_periodo_id: string | null }; Returns: Json }
      fn_grati_trunca: {
        Args: { p_fecha_cese: string | null; p_persona_id: string | null }
        Returns: Json
      }
      fn_grati_trunca_bruta: {
        Args: { p_fecha_cese: string | null; p_persona_id: string | null }
        Returns: Json
      }
      fn_guardar_area: {
        Args: {
          p_codigo: string | null
          p_nombre: string | null
          p_operativa: boolean | null
          p_orden?: number | null
        }
        Returns: undefined
      }
      fn_guardar_sede: {
        Args: {
          p_codigo: string | null
          p_es_alta?: boolean | null
          p_id?: string | null
          p_nombre: string | null
          p_tipo?: string | null
        }
        Returns: undefined
      }
      fn_historial_salario: {
        Args: { p_persona_id: string | null }
        Returns: {
          asignado_por: string
          created_at: string
          nota: string
          rango: string
          salario_mensual_soles: number
          vigente_desde: string
          vigente_hasta: string
        }[]
      }
      fn_horario_retroactivo_preview: {
        Args: { p_horario: Json | null; p_persona_id: string | null; p_vigente_desde: string | null }
        Returns: {
          fecha: string
          horas_extra_actual: number
          horas_extra_nuevo: number
          horas_trabajadas_actual: number
          horas_trabajadas_nuevo: number
          minutos_salida_temprana_actual: number
          minutos_salida_temprana_nuevo: number
          minutos_tarde_actual: number
          minutos_tarde_nuevo: number
          tiene_expediente_formal: boolean
        }[]
      }
      fn_hoy_lima: { Args: never; Returns: string }
      fn_ingresos: { Args: never; Returns: Json }
      fn_jornadas_extra: {
        Args: { p_desde: string | null; p_hasta: string | null; p_persona_id?: string | null }
        Returns: Json
      }
      fn_justificar_falta: {
        Args: {
          p_fecha: string | null
          p_motivo: string | null
          p_observacion?: string | null
          p_persona_id: string | null
        }
        Returns: undefined
      }
      fn_levantar_sello_si_el_dia_cuadra: {
        Args: { p_fecha: string | null; p_persona_id: string | null }
        Returns: number
      }
      fn_levantar_tardanza: {
        Args: {
          p_fecha: string | null
          p_motivo: string | null
          p_observacion?: string | null
          p_persona_id: string | null
        }
        Returns: undefined
      }
      fn_liquidacion: {
        Args: { p_fecha_cese?: string | null; p_persona_id: string | null }
        Returns: Json
      }
      fn_liquidacion_anular: {
        Args: { p_motivo: string | null; p_persona_id: string | null }
        Returns: Json
      }
      fn_liquidacion_descuentos_del_cese: {
        Args: { p_persona_id: string | null }
        Returns: {
          concepto: string
          monto: number
          periodo_estado: string
          periodo_fin: string
          periodo_id: string
          periodo_ini: string
          registrado_el: string
        }[]
      }
      fn_liquidacion_diferencias: {
        Args: { p_persona_id: string | null }
        Returns: {
          ahora: number
          concepto: string
          diferencia: number
          origen: string
          pagado: number
        }[]
      }
      fn_liquidacion_pagar: {
        Args: {
          p_fecha_pago?: string | null
          p_nota?: string | null
          p_persona_id: string | null
        }
        Returns: Json
      }
      fn_liquidaciones_del_periodo: {
        Args: { p_periodo_id: string | null }
        Returns: Json
      }
      fn_liquidaciones_pendientes: {
        Args: never
        Returns: {
          descuadra: boolean
          descuadra_real: boolean
          dias_restantes: number
          fecha_cese: string
          fecha_ingreso: string
          pagada: boolean
          persona: string
          persona_id: string
          sede: string
          total: number
          vence_el: string
          vencido: boolean
        }[]
      }
      fn_liquidaciones_vencidas_bandeja: {
        Args: never
        Returns: {
          dias_restantes: number
          fecha_cese: string
          pagada: boolean
          persona: string
          persona_id: string
          sede: string
          total: number
          vence_el: string
          vencido: boolean
        }[]
      }
      fn_marca_apartada_reportar: {
        Args: {
          p_client_uuid: string | null
          p_motivo_otro?: string | null
          p_persona_id: string | null
          p_terminal_id?: string | null
          p_timestamp_cliente: string | null
          p_tipo: Database["public"]["Enums"]["tipo_marca"] | null
          p_ultimo_error?: string | null
        }
        Returns: string
      }
      fn_marca_apartada_resolver: {
        Args: { p_id: string | null; p_motivo: string | null; p_resolucion: string | null }
        Returns: Json
      }
      fn_marcar_alerta_resultado: {
        Args: { p_exito: boolean | null; p_id: string | null; p_nota?: string | null }
        Returns: undefined
      }
      fn_marcar_anuncio_leido: { Args: { p_id: string | null }; Returns: undefined }
      fn_marcar_novedad_vista: { Args: { p_novedad_id: string | null }; Returns: undefined }
      fn_marcas_apartadas: {
        Args: never
        Returns: {
          client_uuid: string
          fecha: string
          id: string
          persona: string
          persona_id: string
          reportada_at: string
          sede: string
          timestamp_cliente: string
          tipo: string
          ultimo_error: string
        }[]
      }
      fn_marcas_apartadas_resueltas: {
        Args: { p_client_uuids: string[] | null }
        Returns: string[]
      }
      fn_memos_recientes_respuesta_sancionado: {
        Args: { p_dias?: number | null }
        Returns: {
          correlativo: string
          firmado_at: string
          id: string
          nivel: string
          persona: string
          rechazado_at: string
          tipo_causal: string
        }[]
      }
      fn_mes_planilla_pagado: {
        Args: { p_anio: number | null; p_mes: number | null }
        Returns: boolean
      }
      fn_meses_y_dias: {
        Args: { p_desde: string | null; p_hasta: string | null }
        Returns: {
          dias: number
          meses: number
        }[]
      }
      fn_mi_bono_cumpleanos: {
        Args: never
        Returns: {
          anio: number
          documento_id: string
          entregado_el: string
          estado: string
          mes_cumpleanos: number
          monto: number
          pedido_el: string
          periodo_fin: string
          via: string
        }[]
      }
      fn_mi_firma: { Args: never; Returns: string }
      fn_mi_firma_config: {
        Args: never
        Returns: {
          estilo: string
          imagen: string
          tipo: string
        }[]
      }
      fn_mi_memo: { Args: { p_id: string | null }; Returns: Json }
      fn_mi_rango_actual: { Args: never; Returns: string }
      fn_mis_boletas: {
        Args: never
        Returns: {
          actualizada: boolean
          boleta_id: string | null
          bytes: number
          estado: string | null
          fecha_fin: string
          fecha_ini: string
          n_partes: number
          periodo_id: string
          publicada_at: string | null
          recibida_at: string | null
          tipo: string | null
          version_id: string | null
          version_n: number | null
          vista_at: string | null
        }[]
      }
      fn_mis_medidas: {
        Args: never
        Returns: {
          creado_at: string
          cumplida_at: string | null
          id: string
          instruccion: string
          vigente_hasta: string | null
        }[]
      }
      fn_mis_memos: {
        Args: never
        Returns: {
          correlativo: string
          entregado_at: string
          firma_sancionado_confirmada_at: string
          id: string
          medio_entrega: string
          nivel: string
          sancionado_rechazo_firma_at: string
          tipo_causal: string
        }[]
      }
      fn_mis_memos_por_recibir: {
        Args: never
        Returns: {
          enviado_a_info_at: string
          id: string
        }[]
      }
      fn_mis_solicitudes_perfil: {
        Args: never
        Returns: {
          campo: string
          creada_at: string
          estado: string
          etiqueta: string
          id: string
          motivo: string
          resuelta_at: string
          valor_anterior: Json
          valor_propuesto: Json
        }[]
      }
      fn_movilidad_revisiones_pedidas: {
        Args: { p_solo_pendientes?: boolean | null }
        Returns: Json
      }
      fn_objetivo_agregar: {
        Args: {
          p_anio: number | null
          p_descripcion: string | null
          p_indicaciones?: string | null
          p_mes: number | null
          p_persona_id: string | null
        }
        Returns: Json
      }
      fn_objetivo_editar: {
        Args: {
          p_descripcion: string | null
          p_indicaciones?: string | null
          p_item_id: string | null
        }
        Returns: undefined
      }
      fn_objetivo_eliminar: { Args: { p_item_id: string | null }; Returns: undefined }
      fn_objetivo_marcar: {
        Args: { p_cumplido: boolean | null; p_item_id: string | null }
        Returns: undefined
      }
      fn_objetivos_checklist: {
        Args: { p_anio: number | null; p_mes: number | null; p_persona_id?: string | null }
        Returns: Json
      }
      fn_objetivos_copiar_mes_anterior: {
        Args: { p_anio: number | null; p_mes: number | null; p_persona_id: string | null }
        Returns: Json
      }
      fn_objetivos_historial: {
        Args: {
          p_anio: number | null
          p_mes: number | null
          p_meses?: number | null
          p_persona_id: string | null
        }
        Returns: Json
      }
      fn_objetivos_resumen: {
        Args: { p_anio: number | null; p_mes: number | null }
        Returns: Json
      }
      fn_objetivos_sync_mes: {
        Args: { p_anio: number | null; p_mes: number | null; p_persona_id: string | null }
        Returns: undefined
      }
      fn_organo_titulo_x_cerrar: {
        Args: {
          p_hasta: string | null
          p_id: string | null
          p_motivo: string | null
        }
        Returns: undefined
      }
      fn_organo_titulo_x_guardar: {
        Args: {
          p_acta: string | null
          p_desde: string | null
          p_papel: string | null
          p_persona: string | null
          p_sede: string | null
        }
        Returns: string
      }
      fn_organos_titulo_x: {
        Args: never
        Returns: {
          acta: string | null
          desde: string
          hasta: string | null
          id: string
          nombre: string
          papel: string
          persona_id: string
          sede_codigo: string
          sede_nombre: string
        }[]
      }
      fn_otorgar_descanso_sustitutorio: {
        Args: {
          p_acta_ref?: string | null
          p_estado?: string | null
          p_fecha_descanso: string | null
          p_fecha_feriado: string | null
          p_motivo_fuera_de_plazo?: string | null
          p_persona_id: string | null
        }
        Returns: string
      }
      fn_papeles_cese: { Args: { p_persona_id: string | null }; Returns: Json }
      fn_pedir_revision: {
        Args: { p_comentario: string | null; p_fecha: string | null }
        Returns: undefined
      }
      fn_pedir_revision_contrato: {
        Args: { p_motivo: string | null }
        Returns: undefined
      }
      fn_pedir_revision_movilidad: {
        Args: { p_motivo: string | null }
        Returns: undefined
      }
      fn_periodo_grupos_estado: {
        Args: { p_periodo_id: string | null }
        Returns: {
          estado: string
          grupo: string
          pagado_at: string
          pagado_por_nombre: string
          personas: number
        }[]
      }
      fn_periodo_pagado: {
        Args: { p_grupo?: string | null; p_pagado: boolean | null; p_periodo_id: string | null }
        Returns: undefined
      }
      fn_periodos: { Args: never; Returns: Json }
      fn_permitir_bono_regular: {
        Args: { p_motivo: string | null; p_persona_id: string | null }
        Returns: string
      }
      fn_persona_actual_id: { Args: never; Returns: string }
      fn_persona_en_roster_terminal: {
        Args: { p_persona_id: string | null }
        Returns: boolean
      }
      fn_persona_le_corresponde_movilidad: {
        Args: { p_persona_id: string | null }
        Returns: boolean
      }
      fn_persona_liquidada: { Args: { p_persona_id: string | null }; Returns: boolean }
      fn_persona_marca_en_sede: {
        Args: { p_persona_id: string | null; p_sede_id: string | null }
        Returns: boolean
      }
      fn_personas_funciones: { Args: never; Returns: Json }
      fn_personas_parecidas: {
        Args: { p_apellidos: string | null; p_nombres: string | null }
        Returns: {
          apellidos: string
          estado: string
          fecha_cese: string | null
          fecha_ingreso: string
          nombres: string
          persona_id: string
          sede_codigo: string | null
        }[]
      }
      fn_personas_sin_horario_vigente: {
        Args: { p_dias?: number | null }
        Returns: {
          dias: number
          nombre: string
          nunca_tuvo_horario: boolean
          persona_id: string
          primer_dia: string
          sede: string
          ultimo_dia: string
        }[]
      }
      fn_planilla_calcular: {
        Args: { p_fin: string | null; p_ini: string | null; p_periodo_id?: string | null }
        Returns: Json
      }
      fn_planilla_calcular_nucleo: {
        Args: { p_fin: string | null; p_ini: string | null; p_periodo_id?: string | null }
        Returns: Json
      }
      fn_planilla_calcular_persona: {
        Args: { p_periodo_id: string | null; p_persona_id: string | null }
        Returns: Json
      }
      fn_planilla_congelar: {
        Args: {
          p_autor: string | null
          p_grupo?: string | null
          p_origen: string | null
          p_periodo_id: string | null
        }
        Returns: number
      }
      fn_planilla_congelar_pendientes: { Args: never; Returns: number }
      fn_planilla_foto_diferencias: {
        Args: { p_periodo_id: string | null }
        Returns: {
          diferencia: number
          nombre: string
          persona_id: string
          total_ahora: number
          total_foto: number
        }[]
      }
      fn_planilla_variacion: {
        Args: { p_periodo_id: string | null; p_previo_id?: string | null }
        Returns: Json
      }
      fn_poblacion_obligada: { Args: never; Returns: string[] }
      fn_politica_salarial_vigente: { Args: never; Returns: Json }
      fn_provisiones: {
        Args: { p_as_of?: string | null; p_salario_asof?: string | null }
        Returns: Json
      }
      fn_proyeccion_periodo: { Args: { p_periodo_id: string | null }; Returns: Json }
      fn_proyeccion_planilla: {
        Args: { p_anio: number | null; p_mes: number | null }
        Returns: Json
      }
      fn_publicar_anuncio: {
        Args: { p_cuerpo: string | null; p_sede_id?: string | null; p_titulo: string | null }
        Returns: string
      }
      fn_publicar_documento: {
        Args: {
          p_documento: string | null
          p_etiqueta?: string | null
          p_notas?: string | null
          p_tipo: string | null
          p_titulo: string | null
          p_vigente_desde?: string | null
        }
        Returns: number
      }
      fn_publicar_politica_salarial: {
        Args: { p_documento: string | null; p_notas?: string | null }
        Returns: Json
      }
      fn_puede_gestionar_objetivos: {
        Args: { p_persona_id: string | null }
        Returns: boolean
      }
      fn_quitar_aceptacion: {
        Args: {
          p_fecha: string | null
          p_motivo: string | null
          p_persona_id: string | null
          p_tipo: string | null
        }
        Returns: undefined
      }
      fn_quitar_descanso_sustitutorio: {
        Args: { p_id: string | null }
        Returns: undefined
      }
      fn_quitar_feriado: { Args: { p_fecha: string | null }; Returns: undefined }
      fn_quitar_justificacion: {
        Args: { p_fecha: string | null; p_persona_id: string | null }
        Returns: undefined
      }
      fn_quitar_levantamiento: {
        Args: { p_fecha: string | null; p_persona_id: string | null }
        Returns: undefined
      }
      fn_quitar_movimiento: {
        Args: { p_movimiento_id: string | null }
        Returns: undefined
      }
      fn_quitar_rendimiento: {
        Args: { p_anio: number | null; p_mes: number | null; p_persona_id: string | null }
        Returns: undefined
      }
      fn_quitar_revision: { Args: { p_fecha: string | null }; Returns: undefined }
      fn_quitar_turno: {
        Args: { p_fecha: string | null; p_persona_id: string | null }
        Returns: undefined
      }
      fn_quitar_vacaciones: { Args: { p_id: string | null }; Returns: undefined }
      fn_reabrir_dia: {
        Args: { p_motivo: string | null; p_persona_id: string | null }
        Returns: Json
      }
      fn_reactivar_marcaje: {
        Args: { p_marcaje_id: string | null; p_motivo: string | null }
        Returns: {
          anulada_at: string | null
          anulada_motivo: string | null
          anulada_por: string | null
          client_uuid: string
          confirmo_sin_refrigerio: boolean | null
          estado_revision: Database["public"]["Enums"]["estado_revision"]
          fecha_jornada: string | null
          id: string
          motivo_otro: string | null
          origen: Database["public"]["Enums"]["origen_marca"]
          persona_id: string
          sede_id: string
          server_received_at: string
          terminal_id: string | null
          timestamp_marca: string
          tipo: Database["public"]["Enums"]["tipo_marca"]
        }
        SetofOptions: {
          from: "*"
          to: "marcajes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      fn_reactivar_persona: {
        Args: { p_persona_id: string | null }
        Returns: undefined
      }
      fn_recalcular_jornada: {
        Args: { p_fecha: string | null; p_persona_id: string | null }
        Returns: undefined
      }
      fn_rechazar_firma_memo: { Args: { p_id: string | null }; Returns: undefined }
      fn_recibir_memo_digital: {
        Args: { p_firmar: boolean | null; p_id: string | null }
        Returns: undefined
      }
      fn_regenerar_pin: { Args: { p_persona_id: string | null }; Returns: string }
      fn_regimen_pension_divergentes: {
        Args: never
        Returns: {
          dice_la_ficha: string
          estado: string
          nombre: string
          paga_la_planilla: string
          persona_id: string
          tramo_desde: string
        }[]
      }
      fn_registrar_acta_descanso: {
        Args: { p_nombre?: string | null; p_path: string | null; p_referencia: string | null }
        Returns: string
      }
      fn_registrar_acuse_papel: {
        Args: {
          p_acusado_at?: string | null
          p_documento_id: string | null
          p_nota?: string | null
          p_path: string | null
          p_persona_id: string | null
        }
        Returns: undefined
      }
      fn_registrar_ausencia: {
        Args: {
          p_doc_colegiatura?: string | null
          p_doc_fecha?: string | null
          p_doc_profesional?: string | null
          p_fecha_fin: string | null
          p_fecha_inicio: string | null
          p_motivo?: string | null
          p_persona_id: string | null
          p_tipo: string | null
        }
        Returns: string
      }
      fn_registrar_desembolso: {
        Args: {
          p_anio: number | null
          p_fecha_pago: string | null
          p_monto: number | null
          p_nota?: string | null
          p_origen: string | null
          p_persona_id: string | null
          p_ventana: string | null
        }
        Returns: string
      }
      fn_registrar_marcaje: {
        Args: {
          p_client_uuid: string | null
          p_confirmo_sin_refrigerio?: boolean | null
          p_motivo_otro?: string | null
          p_origen?: Database["public"]["Enums"]["origen_marca"] | null
          p_persona_id: string | null
          p_sede_id?: string | null
          p_terminal_id?: string | null
          p_timestamp_cliente: string | null
          p_tipo: Database["public"]["Enums"]["tipo_marca"] | null
        }
        Returns: {
          anulada_at: string | null
          anulada_motivo: string | null
          anulada_por: string | null
          client_uuid: string
          confirmo_sin_refrigerio: boolean | null
          estado_revision: Database["public"]["Enums"]["estado_revision"]
          fecha_jornada: string | null
          id: string
          motivo_otro: string | null
          origen: Database["public"]["Enums"]["origen_marca"]
          persona_id: string
          sede_id: string
          server_received_at: string
          terminal_id: string | null
          timestamp_marca: string
          tipo: Database["public"]["Enums"]["tipo_marca"]
        }
        SetofOptions: {
          from: "*"
          to: "marcajes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      fn_registrar_mi_consentimiento: {
        Args: { p_finalidad: string | null; p_texto: string | null }
        Returns: undefined
      }
      fn_reglamento_no_acusado: {
        Args: { p_fecha: string | null; p_persona_id: string | null }
        Returns: string
      }
      fn_remuneracion_computable: {
        Args: {
          p_beneficio?: string | null
          p_fecha_ref: string | null
          p_persona_id: string | null
        }
        Returns: Json
      }
      fn_repagar_periodo: {
        Args: { p_grupo?: string | null; p_motivo: string | null; p_periodo_id: string | null }
        Returns: Json
      }
      fn_reporte_abrir: { Args: { p_reporte: string | null }; Returns: string }
      fn_reporte_adjuntar: {
        Args: {
          p_interno?: boolean | null
          p_path: string | null
          p_reporte: string | null
        }
        Returns: string
      }
      fn_reporte_adjuntos: {
        Args: { p_reporte: string | null }
        Returns: {
          bytes: number | null
          creado_at: string
          es_mio: boolean
          id: string
          interno: boolean
          mimetype: string | null
          storage_path: string
        }[]
      }
      fn_reporte_anotar_accion: {
        Args: {
          p_accion: string | null
          p_nota: string | null
          p_reporte: string | null
        }
        Returns: undefined
      }
      fn_reporte_cerrar: {
        Args: {
          p_reporte: string | null
          p_resultado: string | null
          p_texto: string | null
        }
        Returns: undefined
      }
      fn_reporte_crear: {
        Args: {
          p_espera?: string | null
          p_fecha_hecho: string | null
          p_involucradas?: string[] | null
          p_primera_vez?: boolean | null
          p_relato: string | null
          p_sede: string | null
          p_testigos?: string[] | null
          p_ticket?: string | null
          p_tipo: string | null
          p_urgente?: boolean | null
          p_via: string | null
          p_ya_conversado?: string | null
        }
        Returns: {
          codigo: string
          id: string
        }[]
      }
      fn_reporte_derivar: {
        Args: { p_expediente: string | null; p_reporte: string | null }
        Returns: undefined
      }
      fn_reporte_detalle: {
        Args: { p_reporte: string | null }
        Returns: {
          autora: string | null
          cerrado_at: string | null
          cierre_resultado: string | null
          cierre_texto: string | null
          codigo: string
          creado_at: string
          espera: string | null
          estado: string
          fecha_hecho: string
          gestiona: string | null
          id: string
          mi_papel: string
          relato: string
          respuesta_vence_at: string | null
          sede_codigo: string
          tipo: string
          urgente: boolean
          via: string
        }[]
      }
      fn_reporte_en_revision: {
        Args: { p_reporte: string | null }
        Returns: undefined
      }
      fn_reporte_escalar: {
        Args: { p_motivo: string | null; p_reporte: string | null }
        Returns: undefined
      }
      fn_reporte_eventos: {
        Args: { p_reporte: string | null }
        Returns: {
          at: string
          detalle: Json
          id: string
          quien: string
          tipo: string
        }[]
      }
      fn_reporte_expedientes: {
        Args: { p_reporte: string | null }
        Returns: {
          correlativo: string | null
          creado_at: string
          estado: string
          id: string
          nivel: string
          persona: string
        }[]
      }
      fn_reporte_hilo: {
        Args: { p_reporte: string | null }
        Returns: {
          creado_at: string
          es_mio: boolean
          id: string
          interno: boolean
          quien: string
          texto: string
        }[]
      }
      fn_reporte_indicios_delito: {
        Args: { p_nota: string | null; p_reporte: string | null }
        Returns: undefined
      }
      fn_reporte_lideres: {
        Args: { p_reporte: string | null }
        Returns: {
          id: string
          nombre: string
          sede_codigo: string | null
        }[]
      }
      fn_reporte_medida: {
        Args: {
          p_hasta?: string | null
          p_instruccion: string | null
          p_para: string | null
          p_reporte: string | null
        }
        Returns: string
      }
      fn_reporte_medida_cumplida: {
        Args: { p_medida: string | null }
        Returns: undefined
      }
      fn_reporte_medidas: {
        Args: { p_reporte: string | null }
        Returns: {
          creado_at: string
          cumplida_at: string | null
          id: string
          instruccion: string
          para: string
          vigente_hasta: string | null
        }[]
      }
      fn_reporte_mensaje: {
        Args: {
          p_interno?: boolean | null
          p_reporte: string | null
          p_responde_para?: string | null
          p_texto: string | null
        }
        Returns: string
      }
      fn_reporte_padron: {
        Args: never
        Returns: {
          cargo: string | null
          id: string
          nombre: string
          sede_codigo: string | null
        }[]
      }
      fn_reporte_personas: {
        Args: { p_reporte: string | null }
        Returns: {
          nombre: string
          papel: string
          persona_id: string
        }[]
      }
      fn_reporte_plazo_cumplir: {
        Args: {
          p_clave: string | null
          p_nota: string | null
          p_reporte: string | null
        }
        Returns: undefined
      }
      fn_reporte_plazos: {
        Args: { p_reporte: string | null }
        Returns: {
          anulado_at: string | null
          clave: string
          cumplido_at: string | null
          descripcion: string
          duena: string
          norma: string
          nota: string | null
          vence_at: string
        }[]
      }
      fn_reporte_quien_lo_leera: {
        Args: {
          p_involucradas: string[] | null
          p_sede: string | null
          p_testigos: string[] | null
          p_via: string | null
        }
        Returns: {
          cargo: string
        }[]
      }
      fn_reporte_reclasificar: {
        Args: {
          p_motivo: string | null
          p_reporte: string | null
          p_via: string | null
        }
        Returns: undefined
      }
      fn_reportes_bandeja: {
        Args: never
        Returns: {
          autora: string
          codigo: string
          creado_at: string
          estado: string
          gestiona: string | null
          id: string
          mi_motivo: string
          plazos_vencidos: number
          proximo_norma: string | null
          proximo_plazo: string | null
          proximo_vence_at: string | null
          sede_codigo: string
          semaforo: string | null
          tipo: string
          urgente: boolean
          via: string
        }[]
      }
      fn_reportes_mios: {
        Args: never
        Returns: {
          cerrado_at: string | null
          cierre_texto: string | null
          codigo: string
          creado_at: string
          estado: string
          id: string
          mensajes: number
          respuesta_vence_at: string | null
          sin_leer: number
          tipo: string
          ultimo_mensaje_at: string | null
          via: string
        }[]
      }
      fn_resellar_dia: {
        Args: { p_fecha: string | null; p_persona_id: string | null }
        Returns: undefined
      }
      fn_resolver_seguimiento_planilla: {
        Args: { p_id: string | null; p_nota?: string | null }
        Returns: undefined
      }
      fn_resolver_solicitud_perfil: {
        Args: { p_aprobar: boolean | null; p_id: string | null; p_motivo?: string | null }
        Returns: undefined
      }
      fn_resolver_solicitud_vacaciones: {
        Args: { p_aprobar: boolean | null; p_id: string | null; p_respuesta?: string | null }
        Returns: undefined
      }
      fn_responder_mensaje_encargada: {
        Args: { p_id: string | null; p_respuesta: string | null }
        Returns: undefined
      }
      fn_revertir_pago: {
        Args: { p_grupo?: string | null; p_motivo: string | null; p_periodo_id: string | null }
        Returns: undefined
      }
      fn_revisiones_pedidas: {
        Args: { p_solo_pendientes?: boolean | null }
        Returns: Json
      }
      fn_rol_actual: {
        Args: never
        Returns: Database["public"]["Enums"]["rol_usuario"]
      }
      fn_salarios_vigentes: {
        Args: never
        Returns: {
          persona_id: string
          rango: string
          salario_mensual_soles: number
          vigente_desde: string
        }[]
      }
      fn_sede_activa: {
        Args: { p_activa: boolean | null; p_codigo: string | null }
        Returns: undefined
      }
      fn_sede_actual_persona: { Args: never; Returns: string }
      fn_sede_actual_terminal: { Args: never; Returns: string }
      fn_set_cargo: {
        Args: { p_cargo: string | null; p_persona_id: string | null }
        Returns: undefined
      }
      fn_set_categoria: {
        Args: {
          p_criterio: string | null
          p_funciones: string | null
          p_proposito: string | null
          p_rango: string | null
          p_requisitos: string | null
          p_salario_declarado: number | null
        }
        Returns: undefined
      }
      fn_set_con_hijos: {
        Args: { p_con_hijos: boolean | null; p_persona_id: string | null }
        Returns: undefined
      }
      fn_set_cuenta_de_servicio: {
        Args: { p_motivo?: string | null; p_persona_id: string | null; p_valor: boolean | null }
        Returns: undefined
      }
      fn_set_datos_personales: {
        Args: {
          p_celular?: string | null
          p_cuspp?: string | null
          p_direccion?: string | null
          p_discapacidad?: boolean | null
          p_discapacidad_conadis?: string | null
          p_emergencia_nombre?: string | null
          p_emergencia_telefono?: string | null
          p_emergencia_vinculo?: string | null
          p_entidad_bancaria?: string | null
          p_estado_civil?: string | null
          p_fecha_nacimiento?: string | null
          p_foto_dni_url?: string | null
          p_foto_personal_url?: string | null
          p_foto_profesional_url?: string | null
          p_genero?: string | null
          p_grado_instruccion?: string | null
          p_hijos_menores?: boolean | null
          p_nombre_dni?: string | null
          p_numero_cuenta?: string | null
          p_persona_id: string | null
        }
        Returns: undefined
      }
      fn_set_derechohabiente: {
        Args: {
          p_apellidos: string | null
          p_documento?: string | null
          p_essalud?: boolean | null
          p_fecha_nacimiento?: string | null
          p_id: string | null
          p_nombres: string | null
          p_nota?: string | null
          p_persona_id: string | null
          p_vida_ley?: boolean | null
          p_vinculo: string | null
        }
        Returns: string
      }
      fn_set_descanso: {
        Args: { p_fecha: string | null; p_persona_id: string | null }
        Returns: undefined
      }
      fn_set_devenga_beneficio: {
        Args: { p_beneficio: string | null; p_devenga: boolean | null; p_persona_id: string | null }
        Returns: undefined
      }
      fn_set_devenga_beneficios: {
        Args: { p_devenga: boolean | null; p_hasta?: string | null; p_persona_id: string | null }
        Returns: undefined
      }
      fn_set_documento: {
        Args: {
          p_documento: string | null
          p_motivo: string | null
          p_persona_id: string | null
          p_tipo_documento?: string | null
        }
        Returns: undefined
      }
      fn_set_email: {
        Args: { p_email: string | null; p_persona_id: string | null }
        Returns: undefined
      }
      fn_set_encargada_piso: {
        Args: { p_persona_id: string | null; p_valor: boolean | null }
        Returns: undefined
      }
      fn_set_fecha_ingreso: {
        Args: { p_fecha: string | null; p_persona_id: string | null }
        Returns: undefined
      }
      fn_set_feriado: {
        Args: { p_fecha: string | null; p_nombre: string | null }
        Returns: undefined
      }
      fn_set_fin_contrato: {
        Args: { p_fecha: string | null; p_motivo?: string | null; p_persona_id: string | null }
        Returns: undefined
      }
      fn_set_fin_contrato_nucleo: {
        Args: { p_fecha: string | null; p_motivo: string | null; p_persona_id: string | null }
        Returns: undefined
      }
      fn_set_funcion: {
        Args: { p_funcion: string | null; p_persona_id: string | null }
        Returns: undefined
      }
      fn_set_horario_semanal: {
        Args: {
          p_horario: Json | null
          p_motivo: string | null
          p_persona_id: string | null
          p_vigente_desde: string | null
        }
        Returns: undefined
      }
      fn_set_justificacion: {
        Args: {
          p_fecha: string | null
          p_motivo: string | null
          p_observacion?: string | null
          p_persona_id: string | null
        }
        Returns: undefined
      }
      fn_set_meta_cobertura:
        | {
            Args: { p_dia_semana: number | null; p_meta: number | null; p_sede_id: string | null }
            Returns: undefined
          }
        | {
            Args: {
              p_dia_semana: number | null
              p_meta_manana: number | null
              p_meta_tarde: number | null
              p_sede_id: string | null
            }
            Returns: undefined
          }
      fn_set_meta_encargadas: {
        Args: { p_dia_semana: number | null; p_meta: number | null; p_sede_id: string | null }
        Returns: undefined
      }
      fn_set_mi_firma: {
        Args: { p_dataurl: string | null; p_estilo?: string | null; p_tipo?: string | null }
        Returns: undefined
      }
      fn_set_objetivos: {
        Args: {
          p_anio: number | null
          p_cumplidos: number | null
          p_mes: number | null
          p_persona_id: string | null
          p_total?: number | null
        }
        Returns: undefined
      }
      fn_set_practicante_modalidad: {
        Args: { p_modalidad: string | null; p_persona_id: string | null }
        Returns: undefined
      }
      fn_set_regimen_pension: {
        Args: { p_persona_id: string | null; p_regimen: string | null }
        Returns: undefined
      }
      fn_set_rendimiento: {
        Args: {
          p_anio: number | null
          p_etiqueta_codigo?: string | null
          p_mes: number | null
          p_persona_id: string | null
          p_porcentaje: number | null
        }
        Returns: undefined
      }
      fn_set_retencion_4ta: {
        Args: {
          p_constancia_hasta?: string | null
          p_modo: string | null
          p_persona_id: string | null
        }
        Returns: undefined
      }
      fn_set_rol: {
        Args: {
          p_nuevo_rol: Database["public"]["Enums"]["rol_usuario"] | null
          p_persona_id: string | null
        }
        Returns: undefined
      }
      fn_set_salario: {
        Args: {
          p_nota?: string | null
          p_persona_id: string | null
          p_rango: string | null
          p_salario: number | null
          p_vigente_desde: string | null
        }
        Returns: undefined
      }
      fn_set_sede_base: {
        Args: { p_persona_id: string | null; p_sede_id: string | null }
        Returns: undefined
      }
      fn_set_sueldo_base_legal: {
        Args: { p_monto: number | null; p_persona_id: string | null }
        Returns: undefined
      }
      fn_set_tipo_vinculo: {
        Args: { p_persona_id: string | null; p_tipo: string | null }
        Returns: undefined
      }
      fn_set_turno: {
        Args: {
          p_fecha: string | null
          p_hora_entrada: string | null
          p_hora_salida: string | null
          p_persona_id: string | null
        }
        Returns: undefined
      }
      fn_set_vacaciones: {
        Args: {
          p_fecha_fin: string | null
          p_fecha_inicio: string | null
          p_observacion?: string | null
          p_persona_id: string | null
        }
        Returns: string
      }
      fn_set_visible_todas_sedes: {
        Args: { p_persona_id: string | null; p_valor: boolean | null }
        Returns: undefined
      }
      fn_siguiente_tipo_esperado: {
        Args: { p_fecha: string | null; p_persona_id: string | null }
        Returns: Database["public"]["Enums"]["tipo_marca"]
      }
      fn_simular_planilla: {
        Args: { p_fin: string | null; p_ini: string | null }
        Returns: Json
      }
      fn_sin_constancia_del_reglamento: {
        Args: never
        Returns: {
          motivo: string
          persona_id: string
        }[]
      }
      fn_snapshot_valor_actual: {
        Args: { p_campo: string | null; p_persona_id: string | null }
        Returns: Json
      }
      fn_solicitar_vacaciones: {
        Args: {
          p_comentario?: string | null
          p_fecha_fin: string | null
          p_fecha_inicio: string | null
        }
        Returns: string
      }
      fn_solicitud_perfil_puede_escribir: {
        Args: { p_path: string | null }
        Returns: boolean
      }
      fn_solicitud_perfil_puede_leer: {
        Args: { p_path: string | null }
        Returns: boolean
      }
      fn_solicitud_perfil_ruta_congelada: {
        Args: { p_path: string | null }
        Returns: boolean
      }
      fn_solicitudes_perfil_pendientes: {
        Args: never
        Returns: {
          campo: string
          creada_at: string
          etiqueta: string
          id: string
          nombre: string
          persona_id: string
          rutas_adjuntas: string[]
          sede: string
          solo_do: boolean
          valor_anterior: Json
          valor_propuesto: Json
        }[]
      }
      fn_solicitudes_vacaciones: {
        Args: { p_solo_pendientes?: boolean | null }
        Returns: {
          comentario: string
          dias: number
          estado: string
          fecha_fin: string
          fecha_inicio: string
          id: string
          nombre: string
          pedida_at: string
          persona_id: string
          respuesta: string
          resuelta_at: string
          resuelta_por_nombre: string
          sede: string
        }[]
      }
      fn_subir_acta_descanso: {
        Args: { p_dataurl: string | null; p_nombre?: string | null; p_referencia: string | null }
        Returns: string
      }
      fn_sumar_dias_habiles: {
        Args: { p_desde: string | null; p_dias: number | null }
        Returns: string
      }
      fn_tardanza_es_medible: { Args: { p_minutos: number | null }; Returns: boolean }
      fn_tardanza_escalon: {
        Args: { p_persona_id: string | null }
        Returns: {
          bloqueado: boolean
          corte: string
          doc_previo: string
          minimo: number
          nivel_siguiente: string
          suspension_previa_dias: number
        }[]
      }
      fn_tardanza_escalon_al: {
        Args: { p_al: string | null; p_persona_id: string | null }
        Returns: {
          bloqueado: boolean
          corte: string
          doc_previo: string
          minimo: number
          nivel_siguiente: string
          suspension_previa_dias: number
        }[]
      }
      fn_tardanza_ya_documentada: {
        Args: { p_fecha: string | null; p_persona_id: string | null }
        Returns: boolean
      }
      fn_tardanzas_resumen: {
        Args: { p_as_of?: string | null }
        Returns: {
          minimo: number
          nivel_siguiente: string
          nombre: string
          persona_id: string
          sede: string
          sin_medir: number
          tardanzas_mes: number
          ultima_fecha: string
          umbral: string
        }[]
      }
      fn_tipos_ausencia: {
        Args: never
        Returns: {
          activo: boolean
          alerta_desde: number | null
          codigo: string
          descuenta_vacaciones: boolean
          nombre: string
          orden: number
          paga: boolean
          requiere_aprobacion: boolean
          requiere_documento: boolean
          ventana_alerta_dias: number | null
        }[]
        SetofOptions: {
          from: "*"
          to: "tipos_ausencia"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      fn_turno_texto: {
        Args: { p_entrada: string | null; p_es_descanso: boolean | null; p_salida: string | null }
        Returns: string
      }
      fn_vacaciones_por_atender: { Args: never; Returns: number }
      fn_vacaciones_por_vencer: {
        Args: { p_as_of?: string | null; p_dias?: number | null }
        Returns: {
          dias_para_vencer: number
          dias_pendientes: number
          fecha_ingreso: string
          persona: string
          persona_id: string
          records_sin_gozar: number
          records_vencidos: number
          sede: string
          vence_el: string
        }[]
      }
      fn_vacaciones_resumen: { Args: { p_as_of?: string | null }; Returns: Json }
      fn_vacaciones_saldo: {
        Args: { p_as_of?: string | null; p_persona_id: string | null }
        Returns: Json
      }
      fn_vacaciones_saldo_interno: {
        Args: { p_as_of?: string | null; p_persona_id: string | null }
        Returns: Json
      }
      fn_vacaciones_truncas: {
        Args: { p_fecha_cese: string | null; p_persona_id: string | null }
        Returns: Json
      }
      fn_validar_valor_propuesto: {
        Args: { p_campo: string | null; p_valor: Json | null }
        Returns: undefined
      }
      fn_ve_casos: { Args: never; Returns: boolean }
      fn_ventanas_de_regularidad: {
        Args: { p_fecha: string | null }
        Returns: {
          fin: string
          ini: string
          nombre: string
        }[]
      }
      fn_verificar_corrector: {
        Args: { p_persona_objetivo: string | null }
        Returns: string
      }
    }
    Enums: {
      estado_jornada:
        | "abierta"
        | "en_pausa"
        | "cerrada"
        | "auto_cerrada_pendiente"
        | "revisada"
      estado_revision: "normal" | "pendiente_revision" | "revisada"
      origen_marca:
        | "terminal"
        | "admin_correccion"
        | "auto_cierre"
        | "import_historico"
      rol_usuario: "integrante" | "supervisor_sede" | "lider_do" | "admin"
      tipo_marca:
        | "entrada"
        | "salida_final"
        | "salida_almuerzo"
        | "retorno_almuerzo"
        | "salida_personal"
        | "retorno_personal"
        | "salida_tramite"
        | "retorno_tramite"
        | "salida_medico"
        | "retorno_medico"
        | "salida_otro"
        | "retorno_otro"
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
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
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
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
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      estado_jornada: [
        "abierta",
        "en_pausa",
        "cerrada",
        "auto_cerrada_pendiente",
        "revisada",
      ],
      estado_revision: ["normal", "pendiente_revision", "revisada"],
      origen_marca: [
        "terminal",
        "admin_correccion",
        "auto_cierre",
        "import_historico",
      ],
      rol_usuario: ["integrante", "supervisor_sede", "lider_do", "admin"],
      tipo_marca: [
        "entrada",
        "salida_final",
        "salida_almuerzo",
        "retorno_almuerzo",
        "salida_personal",
        "retorno_personal",
        "salida_tramite",
        "retorno_tramite",
        "salida_medico",
        "retorno_medico",
        "salida_otro",
        "retorno_otro",
      ],
    },
  },
} as const

