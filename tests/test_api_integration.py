import unittest
import requests
import os
import json
from google.cloud import bigquery
from datetime import datetime, timezone  # Add these imports

class TestApiIntegration(unittest.TestCase):
    """Pruebas de integración para verificar que la API expone correctamente los datos de BigQuery"""
    
    @classmethod
    def setUpClass(cls):
        """Configura el entorno para las pruebas"""
        # URL de la API en Cloud Run (se obtiene del entorno)
        cls.api_url = os.environ.get('API_URL', 'https://data-api-HASH-uc.a.run.app')
        
        # Cliente BigQuery para verificación directa
        cls.bq_client = bigquery.Client()
        cls.project_id = os.environ.get('GOOGLE_CLOUD_PROJECT')
        
        # Insertar datos de prueba en BigQuery
        cls._insert_test_data()
    
    @classmethod
    def _insert_test_data(cls):
        """Inserta datos de prueba en BigQuery para verificación"""
        # Updated to use string reference instead of deprecated dataset() method
        table_ref = f"{cls.project_id}.analytics_data.events"
        table = cls.bq_client.get_table(table_ref)
        
        # Datos de prueba con un ID único para identificarlos
        test_event_id = f"test-event-{os.urandom(4).hex()}"
        rows_to_insert = [
            {
                "event_id": test_event_id,
                "event_data": json.dumps({"test_key": "test_value"}),
                "timestamp": datetime.now(timezone.utc).isoformat()  # Use datetime from standard library
            }
        ]
        
        errors = cls.bq_client.insert_rows_json(table, rows_to_insert)
        if errors:
            raise Exception(f"No se pudieron insertar datos de prueba: {errors}")
            
        # Guardar el event_id para verificación posterior
        cls.test_event_id = test_event_id
    
    def test_api_returns_events_from_bigquery(self):
        """Verifica que la API devuelve eventos incluyendo el dato de prueba insertado"""
        # Llamar a la API
        response = requests.get(f"{self.api_url}/events")
        self.assertEqual(response.status_code, 200, "La API debería responder con éxito")
        
        # Verificar que la respuesta es JSON válido
        try:
            data = response.json()
        except json.JSONDecodeError:
            self.fail("La respuesta no es JSON válido")
        
        # Verificar que hay datos en la respuesta
        self.assertTrue(len(data) > 0, "La API debería devolver al menos un evento")
        
        # Buscar nuestro evento de prueba por ID
        test_event = next((event for event in data if event['event_id'] == self.test_event_id), None)
        self.assertIsNotNone(test_event, "El evento de prueba insertado debería aparecer en la respuesta de la API")
        
        # Verificar que los datos del evento son correctos
        self.assertEqual(test_event['event_data']['test_key'], "test_value", 
                        "Los datos del evento deberían coincidir con los insertados")
    
    def test_api_health_check(self):
        """Verifica que el endpoint de health check responde correctamente"""
        response = requests.get(f"{self.api_url}/health")
        self.assertEqual(response.status_code, 200, "El health check debería responder con éxito")
        
        data = response.json()
        self.assertEqual(data['status'], 'healthy', "El status debería ser 'healthy'")

if __name__ == '__main__':
    unittest.main()