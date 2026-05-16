@description('Name of the App Service web app (must be globally unique)')
param appName string

@description('Azure region — defaults to the resource group location')
param location string = resourceGroup().location

@description('Microsoft Entra tenant ID')
param aadTenantId string

@description('App Registration (client) ID')
param aadClientId string

@description('App Registration client secret (stored as an app setting)')
@secure()
param aadClientSecret string

@description('App Service Plan SKU')
@allowed(['B1', 'B2', 'B3', 'P0v3', 'P1v3'])
param planSku string = 'B1'

// ---------------------------------------------------------------------------
// App Service Plan (Linux)
// ---------------------------------------------------------------------------
resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${appName}-plan'
  location: location
  sku: {
    name: planSku
  }
  kind: 'linux'
  properties: {
    reserved: true   // required for Linux
  }
}

// ---------------------------------------------------------------------------
// Web App — Python 3.11
// ---------------------------------------------------------------------------
resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: appName
  location: location
  kind: 'app,linux'
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.12'
      appCommandLine: 'gunicorn --config gunicorn.conf.py "app:create_app()"'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      healthCheckPath: '/healthz'
      appSettings: [
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'true' }
        { name: 'ENABLE_ORYX_BUILD',              value: 'true' }
        // Passed to Easy Auth authV2 config below; also available to app code.
        { name: 'AAD_TENANT_ID',    value: aadTenantId   }
        { name: 'AAD_CLIENT_ID',    value: aadClientId   }
        { name: 'AAD_CLIENT_SECRET',value: aadClientSecret }
      ]
    }
  }
}

// ---------------------------------------------------------------------------
// Easy Auth v2 — Microsoft Entra provider
//
// globalValidation.unauthenticatedClientAction = AllowAnonymous so that the
// landing page (/) is reachable without a token.  Per-route role enforcement
// is done in Flask via the @require_roles decorator.
// ---------------------------------------------------------------------------
resource authSettings 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: webApp
  name: 'authsettingsV2'
  properties: {
    globalValidation: {
      requireAuthentication: false
      unauthenticatedClientAction: 'AllowAnonymous'
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          clientId: aadClientId
          clientSecretSettingName: 'AAD_CLIENT_SECRET'
          openIdIssuer: 'https://login.microsoftonline.com/${aadTenantId}/v2.0'
        }
        validation: {
          allowedAudiences: [
            'api://${aadClientId}'
          ]
        }
        login: {
          disableWWWAuthenticate: false
        }
      }
    }
    login: {
      tokenStore: {
        enabled: true
      }
      routes: {}
      cookieExpiration: {
        convention: 'FixedTime'
        timeToExpiration: '08:00:00'
      }
    }
    httpSettings: {
      requireHttps: true
      routes: {
        apiPrefix: '/.auth'
      }
    }
    platform: {
      enabled: true
      runtimeVersion: '~1'
    }
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'
output webAppName string = webApp.name
output principalId string = webApp.identity == null ? '' : webApp.identity.principalId
